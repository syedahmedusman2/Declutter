import XCTest
@testable import DeclutterCore

final class MonitoringPhase4Tests: XCTestCase {
    func testNewFileIsOrganizedOnceItIsStable() async throws {
        let rig = try MonitorRig()
        await rig.start()
        rig.files.addFile("report.pdf", fileID: "report")
        rig.emit("report.pdf", id: 1)
        await rig.drive { rig.files.exists("PDFs/report.pdf") }
        XCTAssertTrue(rig.files.exists("PDFs/report.pdf"))
        XCTAssertFalse(rig.files.exists("report.pdf"))
        await rig.coordinator.stop()
    }

    func testGrowingFileStaysUntilTheSizeStopsChanging() async throws {
        let rig = try MonitorRig()
        await rig.start()
        rig.files.addFile("growing.pdf", fileID: "growing", contents: String(repeating: "x", count: 20), growOnce: true)
        rig.emit("growing.pdf", id: 1)
        await rig.drive { rig.files.attributeReadCount(fileID: "growing") >= 2 && rig.files.exists("growing.pdf") }
        XCTAssertFalse(rig.files.exists("PDFs/growing.pdf"), "sizes \(rig.files.seenSizes(fileID: "growing"))")
        await rig.drive { rig.files.exists("PDFs/growing.pdf") }
        XCTAssertTrue(rig.files.exists("PDFs/growing.pdf"))
        XCTAssertFalse(rig.files.exists("growing.pdf"))
        await rig.coordinator.stop()
    }

    func testBurstOf200FilesDrainsAfterOneDebounce() async throws {
        let queue = CandidateQueue(debounce: 0.5)
        let now = Date(timeIntervalSince1970: 10)
        for index in 0..<200 {
            await queue.enqueue(path: "/Downloads/file-\(index).pdf", eventID: UInt64(index), now: now)
        }
        let queued = await queue.waitingCount
        XCTAssertEqual(queued, 200)
        await queue.enqueue(path: "/Downloads/file-0.pdf", eventID: 500, now: now.addingTimeInterval(0.1))
        let deduped = await queue.waitingCount
        XCTAssertEqual(deduped, 200)
        let early = await queue.drainReady(now: now.addingTimeInterval(0.4))
        XCTAssertTrue(early.isEmpty)
        let drained = await queue.drainReady(now: now.addingTimeInterval(0.6))
        XCTAssertEqual(drained.count, 200)
        XCTAssertEqual(drained.first { $0.path.hasSuffix("file-0.pdf") }?.eventID, 500)
    }

    func testBurstOf200FilesIsOrganized() async throws {
        let rig = try MonitorRig()
        await rig.start()
        for index in 0..<200 {
            rig.files.addFile("file-\(index).pdf", fileID: "id-\(index)")
            rig.emit("file-\(index).pdf", id: UInt64(index + 1))
        }
        try await rig.waitUntil { await rig.coordinator.waitingCount() == 200 }
        await rig.drive { (0..<200).allSatisfy { rig.files.exists("PDFs/file-\($0).pdf") } }
        for index in 0..<200 {
            XCTAssertTrue(rig.files.exists("PDFs/file-\(index).pdf"), "file-\(index).pdf")
        }
        await rig.coordinator.stop()
    }

    func testRenameFromPartialDownloadOrganizesTheFinalFile() async throws {
        let rig = try MonitorRig()
        await rig.start()
        rig.files.addFile("report.pdf.crdownload", fileID: "partial")
        rig.emit("report.pdf.crdownload", id: 1)
        await rig.jumpToNextSleep()
        XCTAssertTrue(rig.files.exists("report.pdf.crdownload"))
        XCTAssertFalse(rig.files.exists("PDFs/report.pdf.crdownload"))
        rig.files.addFile("report.pdf", fileID: "final")
        rig.emit("report.pdf", id: 2)
        await rig.drive { rig.files.exists("PDFs/report.pdf") }
        XCTAssertTrue(rig.files.exists("PDFs/report.pdf"))
        XCTAssertTrue(rig.files.exists("report.pdf.crdownload"))
        await rig.coordinator.stop()
    }

    func testPauseHoldsTheQueueUntilResume() async throws {
        let rig = try MonitorRig()
        await rig.start()
        await rig.coordinator.pause()
        rig.files.addFile("held.pdf", fileID: "held")
        rig.emit("held.pdf", id: 1)
        try await rig.waitUntil { await rig.coordinator.waitingCount() == 1 }
        await rig.clock.advance(by: 1)
        XCTAssertTrue(rig.files.exists("held.pdf"))
        await rig.coordinator.resume()
        await rig.drive { rig.files.exists("PDFs/held.pdf") }
        XCTAssertTrue(rig.files.exists("PDFs/held.pdf"))
        XCTAssertFalse(rig.files.exists("held.pdf"))
        await rig.coordinator.stop()
    }

    func testNewOnlyIgnoresBaselineFileIDs() async throws {
        let rig = try MonitorRig()
        rig.files.addFile("old.pdf", fileID: "old")
        await rig.start(mode: .newOnly)
        rig.emit("old.pdf", id: 1)
        await rig.jumpToNextSleep()
        await rig.jumpToNextSleep()
        XCTAssertTrue(rig.files.exists("old.pdf"))
        XCTAssertFalse(rig.files.exists("PDFs/old.pdf"))
        rig.files.addFile("fresh.pdf", fileID: "fresh")
        rig.emit("fresh.pdf", id: 2)
        await rig.drive { rig.files.exists("PDFs/fresh.pdf") }
        XCTAssertTrue(rig.files.exists("PDFs/fresh.pdf"))
        XCTAssertTrue(rig.files.exists("old.pdf"))
        await rig.coordinator.stop()
    }

    func testExistingAndNewUsesTheSameBaseline() async throws {
        let rig = try MonitorRig()
        rig.files.addFile("old.pdf", fileID: "old")
        await rig.start(mode: .existingAndNew)
        rig.emit("old.pdf", id: 1)
        await rig.jumpToNextSleep()
        await rig.jumpToNextSleep()
        XCTAssertFalse(rig.files.exists("PDFs/old.pdf"))
        await rig.coordinator.stop()
    }

    func testRestartReplaysEventsAfterTheStoredIDAndKeepsTheBaseline() async throws {
        let rig = try MonitorRig()
        rig.files.addFile("old.pdf", fileID: "old")
        await rig.start()
        rig.files.addFile("a.pdf", fileID: "a")
        rig.emit("a.pdf", id: 7)
        await rig.drive { rig.files.exists("PDFs/a.pdf") }
        XCTAssertTrue(rig.files.exists("PDFs/a.pdf"))
        await rig.coordinator.stopForQuit()

        let restarted = rig.makeCoordinator()
        await restarted.start(rig.configuration(mode: .newOnly), recovering: true)
        XCTAssertEqual(rig.events.requestedSince, 7)
        rig.emit("old.pdf", id: 8)
        await rig.jumpToNextSleep()
        await rig.jumpToNextSleep()
        XCTAssertTrue(rig.files.exists("old.pdf"))
        rig.files.addFile("b.pdf", fileID: "b")
        rig.emit("b.pdf", id: 9)
        await rig.drive { rig.files.exists("PDFs/b.pdf") }
        XCTAssertTrue(rig.files.exists("PDFs/b.pdf"))
        await restarted.stop()
    }

    func testNotificationsCoalesceABurstIntoOne() async throws {
        let clock = ManualClock()
        let deliverer = RecordingDeliverer()
        let manager = NotificationManager(clock: clock, deliverer: deliverer)
        for _ in 0..<50 {
            await manager.notify(
                NotificationRequest(kind: .batchCompleted, title: "Files organized", body: "Files organized")
            )
        }
        await advance(clock, by: 5)
        try await waitUntil { await deliverer.snapshot().count == 1 }
        let delivered = await deliverer.snapshot()
        XCTAssertEqual(delivered.map(\.body), ["50 files organized"])
        await manager.cancelPending()
    }

    func testDisabledNotificationIsNotDelivered() async throws {
        let clock = ManualClock()
        let deliverer = RecordingDeliverer()
        let manager = NotificationManager(clock: clock, deliverer: deliverer)
        await manager.update(preferences: NotificationPreferences(enabled: [.batchCompleted: false]))
        await manager.notify(
            NotificationRequest(kind: .batchCompleted, title: "Files organized", body: "Files organized")
        )
        await advance(clock, by: 5)
        let delivered = await deliverer.snapshot()
        XCTAssertTrue(delivered.isEmpty)
    }

    func testBackgroundRunningPolicy() {
        var policy = BackgroundRunningPolicy()
        XCTAssertTrue(policy.menuBarVisible)
        XCTAssertFalse(policy.terminatesWhenLastWindowCloses)
        XCTAssertFalse(policy.shouldPromptBeforeQuit(monitoringActive: true))

        policy.runInBackground = false
        XCTAssertTrue(policy.shouldPromptBeforeQuit(monitoringActive: true))
        policy.alwaysQuit = true
        XCTAssertFalse(policy.shouldPromptBeforeQuit(monitoringActive: true))

        policy = BackgroundRunningPolicy(runInBackground: true, showMenuBarIcon: false)
        XCTAssertTrue(policy.settingMenuBarIcon(to: false).menuBarVisible)
        policy.runInBackground = false
        XCTAssertFalse(policy.settingMenuBarIcon(to: false).menuBarVisible)

        XCTAssertEqual(
            policy.settingLaunchAtLogin(to: true),
            .failure(.launchAtLoginRequiresBackground)
        )
        policy.runInBackground = true
        policy.launchAtLogin = true
        let turnedOff = policy.settingBackground(to: false)
        XCTAssertTrue(turnedOff.loginTurnedOff)
        XCTAssertFalse(turnedOff.policy.launchAtLogin)
        XCTAssertFalse(turnedOff.policy.runInBackground)

        XCTAssertEqual(
            MonitorStatusText.line(state: .monitoring, runInBackground: true, waiting: 0),
            "Monitoring (runs in background)"
        )
        XCTAssertEqual(
            MonitorStatusText.line(state: .monitoring, runInBackground: false, waiting: 0),
            "Monitoring (only while app is open)"
        )
        XCTAssertEqual(MonitorStatusText.line(state: .paused, runInBackground: true, waiting: 0), "Paused")
        XCTAssertEqual(
            MonitorStatusText.line(state: .paused, runInBackground: true, waiting: 2),
            "Monitoring paused, 2 files waiting"
        )
        XCTAssertEqual(MonitorStatusText.line(state: .stopped, runInBackground: false, waiting: 0), "Stopped")
    }
}

private func advance(_ clock: ManualClock, by seconds: TimeInterval) async {
    for _ in 0..<80 {
        if await clock.hasWaiter(dueWithin: seconds) {
            await clock.advance(by: seconds)
            return
        }
        await Task.yield()
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
    if await clock.hasWaiter(dueWithin: seconds) {
        await clock.advance(by: seconds)
    }
}

private func waitUntil(
    timeoutSeconds: Double = 2,
    _ condition: () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTFail("Timed out waiting for monitoring work")
}

private final class MonitorRig {
    let root: TemporaryDirectory
    let support: TemporaryDirectory
    let files: MemoryFileSystem
    let events = ScriptedEventSource()
    let clock = ManualClock()
    let deliverer = RecordingDeliverer()
    let notifications: NotificationManager
    let coordinator: MonitoringCoordinator

    init() throws {
        root = try TemporaryDirectory()
        support = try TemporaryDirectory()
        files = MemoryFileSystem(root: root.url)
        notifications = NotificationManager(clock: clock, deliverer: deliverer)
        coordinator = Self.make(
            root: root.url,
            support: support.url,
            files: files,
            events: events,
            clock: clock,
            notifications: notifications
        )
    }

    func start(mode: AutomationMode = .newOnly) async {
        await coordinator.start(configuration(mode: mode), recovering: false)
    }

    func configuration(mode: AutomationMode) -> MonitorConfiguration {
        MonitorConfiguration(
            sourceRoot: root.url,
            sourceID: UUID(),
            mode: mode,
            categories: [makeCategory(name: "PDFs", extensions: ["pdf"], destination: "PDFs")],
            debounce: 0.5,
            stabilityDelay: 2,
            reconcileInterval: 0
        )
    }

    func emit(_ name: String, id: UInt64) {
        events.emit(FileEvent(path: root.url.appendingPathComponent(name).path, eventID: id))
    }

    func jumpToNextSleep() async {
        for _ in 0..<80 {
            if let wait = await clock.soonestWait() {
                await clock.advance(by: wait)
                return
            }
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        if let wait = await clock.soonestWait() {
            await clock.advance(by: wait)
        }
    }

    func drive(_ condition: () -> Bool) async {
        for _ in 0..<600 {
            if condition() { return }
            if await clock.soonestWait() != nil {
                await jumpToNextSleep()
                if condition() { return }
            } else {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }
    }

    func waitUntil(_ condition: () async -> Bool) async throws {
        try await MonitoringPhase4TestsWait(condition)
    }

    func makeCoordinator() -> MonitoringCoordinator {
        Self.make(
            root: root.url,
            support: support.url,
            files: files,
            events: events,
            clock: clock,
            notifications: notifications
        )
    }

    private static func make(
        root: URL,
        support: URL,
        files: MemoryFileSystem,
        events: ScriptedEventSource,
        clock: ManualClock,
        notifications: NotificationManager
    ) -> MonitoringCoordinator {
        MonitoringCoordinator(
            events: events,
            fileSystem: files,
            organizer: FileOrganizer(fileSystem: files),
            clock: clock,
            notifications: notifications,
            scanner: FileScanner(fileSystem: files),
            baselineStore: BaselineStore(fileURL: support.appendingPathComponent("baseline.json")),
            sessionStore: MonitorSessionStore(fileURL: support.appendingPathComponent("session.json")),
            categories: StaticCategories([makeCategory(name: "PDFs", extensions: ["pdf"], destination: "PDFs")]),
            probe: files
        )
    }
}

private func MonitoringPhase4TestsWait(_ condition: () async -> Bool) async throws {
    try await waitUntil(condition)
}

private final class ScriptedEventSource: FileEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<FileEvent>.Continuation?
    private var pending: [FileEvent] = []
    private(set) var requestedSince: UInt64?

    func events(for root: URL, since eventID: UInt64?) -> AsyncStream<FileEvent> {
        lock.lock()
        requestedSince = eventID
        lock.unlock()
        return AsyncStream { continuation in
            self.lock.lock()
            self.continuation = continuation
            let pending = self.pending
            self.pending = []
            self.lock.unlock()
            pending.forEach { continuation.yield($0) }
        }
    }

    func emit(_ event: FileEvent) {
        lock.lock()
        let continuation = continuation
        if continuation == nil {
            pending.append(event)
        }
        lock.unlock()
        continuation?.yield(event)
    }
}

private actor RecordingDeliverer: NotificationDelivering {
    private var requests: [NotificationRequest] = []

    func deliver(_ request: NotificationRequest) async {
        requests.append(request)
    }

    func snapshot() -> [NotificationRequest] {
        requests
    }
}

private final class MemoryFileSystem: FileSystemProviding, StabilityProbing, @unchecked Sendable {
    struct Node {
        var data: Data
        var isDirectory: Bool
        var fileID: String
        var modified: Date
    }

    private let lock = NSLock()
    private let root: URL
    private var nodes: [String: Node] = [:]
    private var growOnce: Set<String> = []
    private var readCounts: [String: Int] = [:]
    private var seenSizes: [String: [Int64]] = [:]
    private let modified = Date(timeIntervalSince1970: 1_700_000_000)

    init(root: URL) {
        self.root = root
        nodes[key(root)] = Node(data: Data(), isDirectory: true, fileID: "root", modified: modified)
    }

    func addFile(_ name: String, fileID: String, contents: String = "pdf", growOnce: Bool = false) {
        let url = root.appendingPathComponent(name)
        lock.lock()
        nodes[key(url)] = Node(data: Data(contents.utf8), isDirectory: false, fileID: fileID, modified: modified)
        if growOnce { self.growOnce.insert(fileID) }
        lock.unlock()
    }

    func attributeReadCount(fileID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return readCounts[fileID, default: 0]
    }

    func seenSizes(fileID: String) -> [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return seenSizes[fileID, default: []]
    }

    func exists(_ relative: String) -> Bool {
        fileExists(at: root.appendingPathComponent(relative))
    }

    func contentsOfDirectory(at url: URL, including keys: [URLResourceKey]) throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        let prefix = key(url)
        return nodes.keys.compactMap { path in
            guard path != prefix else { return nil }
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
            guard parent == prefix else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    func attributes(of url: URL, keys: Set<URLResourceKey>) throws -> FileAttributes {
        lock.lock()
        defer { lock.unlock() }
        guard let node = nodes[key(url)] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let count = readCounts[node.fileID, default: 0] + 1
        readCounts[node.fileID] = count
        let size: Int64
        if growOnce.contains(node.fileID), count == 1 {
            size = 10
        } else {
            size = Int64(node.data.count)
        }
        seenSizes[node.fileID, default: []].append(size)
        return FileAttributes(
            name: url.lastPathComponent,
            size: size,
            created: modified,
            modified: node.modified,
            isDirectory: node.isDirectory,
            isSymlink: false,
            isAlias: false,
            isHidden: url.lastPathComponent.hasPrefix("."),
            isPackage: false,
            fileIdentifier: node.fileID,
            typeIdentifier: url.pathExtension == "pdf" ? "com.adobe.pdf" : nil
        )
    }

    func fileExists(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return nodes[key(url)] != nil
    }

    func createDirectory(at url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        nodes[key(url)] = Node(data: Data(), isDirectory: true, fileID: "dir-\(url.lastPathComponent)", modified: modified)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let node = nodes.removeValue(forKey: key(source)) else {
            throw CocoaError(.fileNoSuchFile)
        }
        nodes[key(destination)] = node
    }

    func trashItem(at url: URL) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        nodes.removeValue(forKey: key(url))
        return URL(fileURLWithPath: "/tmp/Trash/\(url.lastPathComponent)")
    }

    func probe(_ url: URL) throws -> FileAttributes? {
        guard fileExists(at: url) else { return nil }
        return try attributes(of: url, keys: [])
    }

    func isBusy(_ url: URL) -> Bool {
        false
    }

    private func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
