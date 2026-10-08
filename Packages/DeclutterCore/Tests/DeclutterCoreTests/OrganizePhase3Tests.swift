import XCTest
@testable import DeclutterCore

final class OrganizePhase3Tests: XCTestCase {
    private let fileSystem = SystemFileSystem()

    func testDryRunDoesNotMutateTheDirectory() throws {
        let root = try TemporaryDirectory()
        try root.writeFile("report.pdf", contents: "pdf")
        try root.writeFile("notes.txt", contents: "notes")
        try root.writeFile("photo.jpg", contents: "jpg")
        let before = try fingerprint(root.url)
        let recording = RecordingFileSystem(base: fileSystem)
        let snapshots = try ["report.pdf", "notes.txt", "photo.jpg"].map { try load($0, in: root) }
        let planner = OrganizePlanner(
            fileSystem: recording,
            categories: DefaultCategories.make(),
            sourceRoot: root.url
        )
        let plan = planner.plan(files: snapshots)
        XCTAssertEqual(plan.map(\.predictedStatus), [.success, .success, .success])
        XCTAssertEqual(recording.mutations, 0)
        XCTAssertEqual(try fingerprint(root.url), before)
        XCTAssertFalse(fileSystem.fileExists(at: root.url.appendingPathComponent("PDFs")))
    }

    func testEachConflictPolicy() async throws {
        let root = try TemporaryDirectory()
        let destination = root.url.appendingPathComponent("PDFs/report.pdf")
        try root.writeFile("PDFs/report.pdf", contents: "old")
        let organizer = FileOrganizer(fileSystem: fileSystem)
        let options = OrganizeOptions(workerCount: 1)

        try root.writeFile("report.pdf", contents: "rename")
        let rename = try planned(root, name: "report.pdf", policy: .autoRename)
        XCTAssertEqual(rename.conflict, .autoRename)
        XCTAssertEqual(rename.proposedURL.lastPathComponent, "report (1).pdf")
        let renamed = try await finish(organizer.execute(plan: [rename], sourceRoot: root.url, options: options))
        XCTAssertEqual(renamed.results.first?.status, .success)
        XCTAssertEqual(renamed.results.first?.destinationURL?.lastPathComponent, "report (1).pdf")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old")

        try root.writeFile("report.pdf", contents: "skip")
        let skip = try planned(root, name: "report.pdf", policy: .skip)
        XCTAssertEqual(skip.action, .skip)
        let skipped = try await finish(organizer.execute(plan: [skip], sourceRoot: root.url, options: options))
        XCTAssertEqual(skipped.results.first?.status, .skipped)
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("report.pdf"), encoding: .utf8), "skip")
        try FileManager.default.removeItem(at: root.url.appendingPathComponent("report.pdf"))

        try root.writeFile("report.pdf", contents: "ask")
        let ask = try planned(root, name: "report.pdf", policy: .ask)
        XCTAssertEqual(ask.action, .needsDecision)
        let asked = try await finish(organizer.execute(plan: [ask], sourceRoot: root.url, options: options))
        XCTAssertEqual(asked.results.first?.status, .needsDecision)
        XCTAssertTrue(fileSystem.fileExists(at: root.url.appendingPathComponent("report.pdf")))
        try FileManager.default.removeItem(at: root.url.appendingPathComponent("report.pdf"))

        try root.writeFile("report.pdf", contents: "replace")
        let replace = try planned(root, name: "report.pdf", policy: .replace)
        XCTAssertEqual(replace.action, .replace)
        let unconfirmed = try await finish(
            organizer.execute(plan: [replace], sourceRoot: root.url, options: options, replaceConfirmed: false)
        )
        XCTAssertEqual(unconfirmed.results.first?.status, .needsDecision)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old")

        let confirmed = try await finish(
            organizer.execute(plan: [replace], sourceRoot: root.url, options: options, replaceConfirmed: true)
        )
        XCTAssertEqual(confirmed.results.first?.status, .success)
        XCTAssertEqual(confirmed.results.first?.message, OrganizeMessage.replaced)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "replace")
        XCTAssertFalse(fileSystem.fileExists(at: root.url.appendingPathComponent("report.pdf")))
    }

    func testMissingSourceDoesNotAbortTheBatch() async throws {
        let root = try TemporaryDirectory()
        try root.writeFile("gone.pdf", contents: "gone")
        try root.writeFile("kept.pdf", contents: "kept")
        let gone = try planned(root, name: "gone.pdf", policy: .autoRename, destination: "Out")
        let kept = try planned(root, name: "kept.pdf", policy: .autoRename, destination: "Out")
        try FileManager.default.removeItem(at: root.url.appendingPathComponent("gone.pdf"))
        let batch = try await finish(
            FileOrganizer(fileSystem: fileSystem).execute(
                plan: [gone, kept],
                sourceRoot: root.url,
                options: OrganizeOptions(workerCount: 2)
            )
        )
        XCTAssertEqual(batch.results.first { $0.plannedMoveID == gone.id }?.status, .skipped)
        XCTAssertEqual(batch.results.first { $0.plannedMoveID == gone.id }?.message, OrganizeMessage.disappeared)
        XCTAssertEqual(batch.results.first { $0.plannedMoveID == kept.id }?.status, .success)
        XCTAssertTrue(fileSystem.fileExists(at: root.url.appendingPathComponent("Out/kept.pdf")))
    }

    func testReadOnlyDestinationFailsWithoutAbortingTheBatch() async throws {
        let root = try TemporaryDirectory()
        let locked = root.url.appendingPathComponent("Locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        try root.writeFile("locked.pdf", contents: "locked")
        try root.writeFile("free.pdf", contents: "free")
        let blocked = try planned(root, name: "locked.pdf", policy: .autoRename, destination: "Locked")
        let free = try planned(root, name: "free.pdf", policy: .autoRename, destination: "Free")
        let batch = try await finish(
            FileOrganizer(fileSystem: fileSystem).execute(
                plan: [blocked, free],
                sourceRoot: root.url,
                options: OrganizeOptions(workerCount: 2)
            )
        )
        XCTAssertEqual(batch.results.first { $0.plannedMoveID == blocked.id }?.status, .failed)
        XCTAssertTrue(fileSystem.fileExists(at: root.url.appendingPathComponent("locked.pdf")))
        XCTAssertEqual(batch.results.first { $0.plannedMoveID == free.id }?.status, .success)
        XCTAssertTrue(fileSystem.fileExists(at: root.url.appendingPathComponent("Free/free.pdf")))
    }

    func testDestinationLoopAndSameDirectoryAreRejected() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("Project"), withIntermediateDirectories: true)
        try root.writeFile("notes.txt", contents: "notes")
        let project = try load("Project", in: root)
        let loopCategory = makeCategory(name: "Box", extensions: [], destination: "Project/Nested", isCatchAll: true)
        let loopPlan = OrganizePlanner(fileSystem: fileSystem, categories: [loopCategory], sourceRoot: root.url)
            .plan(files: [project])
        XCTAssertEqual(loopPlan.first?.predictedStatus, .failed)
        XCTAssertEqual(loopPlan.first?.message, OrganizeMessage.loop)
        XCTAssertFalse(fileSystem.fileExists(at: root.url.appendingPathComponent("Project/Nested")))

        let same = try load("notes.txt", in: root)
        let here = makeCategory(name: "Here", extensions: ["txt"], destination: "")
        let samePlan = OrganizePlanner(fileSystem: fileSystem, categories: [here], sourceRoot: root.url)
            .plan(files: [same])
        XCTAssertEqual(samePlan.first?.predictedStatus, .skipped)
        XCTAssertEqual(samePlan.first?.message, OrganizeMessage.sameDirectory)
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("notes.txt"), encoding: .utf8), "notes")
    }

    func testBatchReservationRenamesTheSecondFile() {
        let root = URL(fileURLWithPath: "/Downloads", isDirectory: true)
        let other = URL(fileURLWithPath: "/Inbox", isDirectory: true)
        let files = [
            makeSnapshot(named: "report.pdf", in: root),
            makeSnapshot(named: "report.pdf", in: other),
        ]
        let plan = OrganizePlanner(
            fileSystem: ClosedFileSystem(),
            categories: DefaultCategories.make(),
            sourceRoot: root
        ).plan(files: files)
        XCTAssertEqual(plan[0].proposedURL.lastPathComponent, "report.pdf")
        XCTAssertEqual(plan[1].conflict, .autoRename)
        XCTAssertEqual(plan[1].proposedURL.lastPathComponent, "report (1).pdf")
    }

    func testJournalIsPendingBeforeTheMoveAndReconcilesCrashes() async throws {
        let root = try TemporaryDirectory()
        try root.writeFile("a.pdf", contents: "a")
        let journalURL = root.url.appendingPathComponent("journal.json")
        let watching = PendingWatchFileSystem(journalURL: journalURL)
        let journal = FileJournal(fileURL: journalURL)
        let move = try planned(root, name: "a.pdf", policy: .autoRename, destination: "PDFs")
        let batch = try await finish(
            FileOrganizer(fileSystem: watching, journal: journal).execute(
                plan: [move],
                sourceRoot: root.url,
                options: OrganizeOptions(workerCount: 1)
            )
        )
        XCTAssertTrue(watching.sawPending)
        XCTAssertEqual(batch.results.first?.status, .success)
        let stored = try await journal.load()
        XCTAssertEqual(stored.first?.status, .success)
        XCTAssertNotEqual(stored.first?.status, .pending)

        let source = root.url.appendingPathComponent("still.txt")
        let destination = root.url.appendingPathComponent("gone.txt")
        let neitherSource = root.url.appendingPathComponent("missing-source.txt")
        let neitherDestination = root.url.appendingPathComponent("missing-dest.txt")
        try Data("still".utf8).write(to: source)
        try Data("dest".utf8).write(to: root.url.appendingPathComponent("OnlyDest.txt"))
        try await journal.appendPending(entry(batch: UUID(), source: source, destination: destination))
        try await journal.appendPending(
            entry(batch: UUID(), source: root.url.appendingPathComponent("moved.txt"), destination: root.url.appendingPathComponent("OnlyDest.txt"))
        )
        try await journal.appendPending(entry(batch: UUID(), source: neitherSource, destination: neitherDestination))
        let updated = try await journal.reconcilePending(using: fileSystem)
        XCTAssertEqual(updated, 3)
        let entries = try await journal.load()
        XCTAssertEqual(entries.first { $0.sourcePath == source.path }?.message, "interrupted")
        XCTAssertEqual(entries.first { $0.destinationPath.hasSuffix("OnlyDest.txt") }?.status, .success)
        XCTAssertEqual(entries.first { $0.sourcePath == neitherSource.path }?.message, "missing")
    }

    func testCancellationSkipsFilesThatHaveNotStarted() async throws {
        let root = try TemporaryDirectory()
        for index in 0..<4 {
            try root.writeFile("file-\(index).pdf", contents: "x")
        }
        let plan = try (0..<4).map { try planned(root, name: "file-\($0).pdf", policy: .autoRename, destination: "PDFs") }
        let gate = GateFileSystem()
        let execution = FileOrganizer(fileSystem: gate).execute(
            plan: plan,
            sourceRoot: root.url,
            options: OrganizeOptions(workerCount: 1)
        )
        let started = await waitForStart(gate, timeoutNanoseconds: 5_000_000_000)
        XCTAssertTrue(started)
        execution.cancel()
        gate.unblock()
        let batch = await drain(execution)
        XCTAssertTrue(batch.cancelled)
        XCTAssertEqual(batch.succeeded, 1)
        XCTAssertEqual(batch.results.filter { $0.message == OrganizeMessage.cancelled }.count, 3)
    }

    func testPlanningFiveThousandFilesStaysUnderThreeSeconds() {
        let root = URL(fileURLWithPath: "/Downloads", isDirectory: true)
        let files = (0..<5_000).map { makeSnapshot(named: "file-\($0).pdf", in: root) }
        let planner = OrganizePlanner(
            fileSystem: ClosedFileSystem(),
            categories: DefaultCategories.make(),
            sourceRoot: root
        )
        let start = Date()
        let plan = planner.plan(files: files)
        XCTAssertEqual(plan.count, 5_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertTrue(plan.allSatisfy { $0.categoryName == "PDFs" && $0.predictedStatus == .success })
    }

    private func planned(
        _ root: TemporaryDirectory,
        name: String,
        policy: ConflictPolicy,
        destination: String = "PDFs"
    ) throws -> PlannedMove {
        var category = makeCategory(name: "PDFs", extensions: ["pdf"], destination: destination)
        category.conflictPolicy = policy
        let snapshot = try load(name, in: root)
        let plan = OrganizePlanner(fileSystem: fileSystem, categories: [category], sourceRoot: root.url)
            .plan(files: [snapshot])
        return try XCTUnwrap(plan.first)
    }

    private func load(_ name: String, in root: TemporaryDirectory) throws -> FileSnapshot {
        try FileSnapshotLoader(fileSystem: fileSystem).load(url: root.url.appendingPathComponent(name))
    }

    private func finish(_ execution: OrganizeExecution) async throws -> BatchResult {
        let batch = await drain(execution)
        return batch
    }

    private func drain(_ execution: OrganizeExecution) async -> BatchResult {
        for await _ in execution.progress {}
        return await execution.result.value
    }

    private func entry(batch: UUID, source: URL, destination: URL) -> JournalEntry {
        JournalEntry(
            batchID: batch,
            sourcePath: source.path,
            destinationPath: destination.path,
            originalName: source.lastPathComponent,
            finalName: destination.lastPathComponent,
            categoryName: "PDFs",
            categoryID: nil,
            status: .pending
        )
    }

    private func fingerprint(_ root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var lines: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            let relative = url.path.replacingOccurrences(of: root.path, with: "")
            let text = try String(contentsOf: url, encoding: .utf8)
            lines.append("\(relative)=\(text)")
        }
        return lines.sorted()
    }

    private func waitForStart(_ gate: GateFileSystem, timeoutNanoseconds: UInt64) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await gate.waitForStart(); return true }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }
            let started = await group.next() ?? false
            group.cancelAll()
            return started
        }
    }
}

private final class RecordingFileSystem: FileSystemProviding, @unchecked Sendable {
    let base: any FileSystemProviding
    private let lock = NSLock()
    private var mutationCount = 0
    var mutations: Int { lock.lock(); defer { lock.unlock() }; return mutationCount }

    init(base: any FileSystemProviding) { self.base = base }

    func contentsOfDirectory(at url: URL, including keys: [URLResourceKey]) throws -> [URL] {
        try base.contentsOfDirectory(at: url, including: keys)
    }
    func attributes(of url: URL, keys: Set<URLResourceKey>) throws -> FileAttributes {
        try base.attributes(of: url, keys: keys)
    }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func createDirectory(at url: URL) throws { note(); try base.createDirectory(at: url) }
    func moveItem(at source: URL, to destination: URL) throws { note(); try base.moveItem(at: source, to: destination) }
    func trashItem(at url: URL) throws -> URL { note(); return try base.trashItem(at: url) }
    private func note() { lock.lock(); mutationCount += 1; lock.unlock() }
}

private struct ClosedFileSystem: FileSystemProviding {
    func contentsOfDirectory(at url: URL, including keys: [URLResourceKey]) throws -> [URL] { [] }
    func attributes(of url: URL, keys: Set<URLResourceKey>) throws -> FileAttributes {
        throw CocoaError(.fileReadNoSuchFile)
    }
    func fileExists(at url: URL) -> Bool { false }
    func createDirectory(at url: URL) throws { throw CocoaError(.fileWriteUnknown) }
    func moveItem(at source: URL, to destination: URL) throws { throw CocoaError(.fileWriteUnknown) }
    func trashItem(at url: URL) throws -> URL { throw CocoaError(.fileWriteUnknown) }
}

private final class PendingWatchFileSystem: FileSystemProviding, @unchecked Sendable {
    let base = SystemFileSystem()
    let journalURL: URL
    private let lock = NSLock()
    private var pending = false
    var sawPending: Bool { lock.lock(); defer { lock.unlock() }; return pending }

    init(journalURL: URL) { self.journalURL = journalURL }

    func contentsOfDirectory(at url: URL, including keys: [URLResourceKey]) throws -> [URL] {
        try base.contentsOfDirectory(at: url, including: keys)
    }
    func attributes(of url: URL, keys: Set<URLResourceKey>) throws -> FileAttributes {
        try base.attributes(of: url, keys: keys)
    }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func moveItem(at source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: journalURL)
        let document = try JSONDecoder().decode(JournalDocument.self, from: data)
        let found = document.entries.contains { $0.status == .pending && $0.sourcePath == source.path }
        lock.lock()
        pending = found
        lock.unlock()
        try base.moveItem(at: source, to: destination)
    }
    func trashItem(at url: URL) throws -> URL { try base.trashItem(at: url) }
}

private final class GateFileSystem: FileSystemProviding, @unchecked Sendable {
    let base = SystemFileSystem()
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var waiter: CheckedContinuation<Void, Never>?
    private var opened = false

    func waitForStart() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    func unblock() { release.signal() }

    func contentsOfDirectory(at url: URL, including keys: [URLResourceKey]) throws -> [URL] {
        try base.contentsOfDirectory(at: url, including: keys)
    }
    func attributes(of url: URL, keys: Set<URLResourceKey>) throws -> FileAttributes {
        try base.attributes(of: url, keys: keys)
    }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func moveItem(at source: URL, to destination: URL) throws {
        lock.lock()
        opened = true
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume()
        release.wait()
        try base.moveItem(at: source, to: destination)
    }
    func trashItem(at url: URL) throws -> URL { try base.trashItem(at: url) }
}
