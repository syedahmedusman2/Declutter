import Foundation

public struct FileOrganizationRequest: Sendable {
    public var snapshot: FileSnapshot
    public var category: Category

    public init(snapshot: FileSnapshot, category: Category) {
        self.snapshot = snapshot
        self.category = category
    }
}

public struct FileMoveResult: Sendable, Equatable {
    public var sourceURL: URL
    public var destinationURL: URL?
    public var status: OperationStatus
    public var message: String
    public var plannedMoveID: UUID?

    public init(
        sourceURL: URL,
        destinationURL: URL?,
        status: OperationStatus,
        message: String,
        plannedMoveID: UUID? = nil
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.status = status
        self.message = message
        self.plannedMoveID = plannedMoveID
    }
}

/// Moves files into category folders. Name clashes become `name (1).ext`, then `name (2).ext`.
public struct FileOrganizer: Sendable {
    private let fileSystem: any FileSystemProviding
    private let journal: (any MoveJournal)?
    private let history: (any HistoryRecording)?
    private let resolver = ConflictResolver()

    public init(
        fileSystem: any FileSystemProviding,
        journal: (any MoveJournal)? = nil,
        history: (any HistoryRecording)? = nil
    ) {
        self.fileSystem = fileSystem
        self.journal = journal
        self.history = history
    }

    /// Runs the selected plan with a bounded number of workers. Dry-run planning is separate and is not repeated here.
    public func execute(
        plan: [PlannedMove],
        selection: Set<UUID>? = nil,
        sourceRoot: URL,
        options: OrganizeOptions = OrganizeOptions(),
        replaceConfirmed: Bool = false
    ) -> OrganizeExecution {
        let chosen = plan.filter { selection?.contains($0.id) ?? true }
        let (stream, continuation) = AsyncStream<OrganizeProgress>.makeStream()
        let task = Task {
            defer { continuation.finish() }
            return await self.run(
                chosen,
                sourceRoot: sourceRoot,
                options: options,
                replaceConfirmed: replaceConfirmed,
                progress: continuation
            )
        }
        return OrganizeExecution(progress: stream, result: task)
    }

    private func run(
        _ moves: [PlannedMove],
        sourceRoot: URL,
        options: OrganizeOptions,
        replaceConfirmed: Bool,
        progress: AsyncStream<OrganizeProgress>.Continuation
    ) async -> BatchResult {
        let batchID = UUID()
        progress.yield(OrganizeProgress(completed: 0, total: moves.count, fileName: ""))
        if moves.count > options.maximumBatchSize {
            let results = moves.map {
                result($0.snapshot.url, nil, .skipped, OrganizeMessage.batchLimit(options.maximumBatchSize), id: $0.id)
            }
            progress.yield(OrganizeProgress(completed: moves.count, total: moves.count, fileName: ""))
            return BatchResult(batchID: batchID, results: results, cancelled: false)
        }

        let claims = DestinationClaims(fileSystem: fileSystem, resolver: resolver)
        let counter = ProgressCounter(total: moves.count, continuation: progress)
        var results = Array<FileMoveResult?>(repeating: nil, count: moves.count)
        var nextIndex = 0
        var running = 0
        let workerCount = min(options.workerCount, max(moves.count, 1))

        await withTaskGroup(of: (Int, FileMoveResult).self) { group in
            func schedule() {
                while running < workerCount && nextIndex < moves.count && !Task.isCancelled {
                    let index = nextIndex
                    nextIndex += 1
                    running += 1
                    let move = moves[index]
                    group.addTask {
                        let outcome = await self.executeOne(
                            move,
                            batchID: batchID,
                            sourceRoot: sourceRoot,
                            replaceConfirmed: replaceConfirmed,
                            claims: claims
                        )
                        await counter.finishOne(fileName: move.snapshot.name)
                        return (index, outcome)
                    }
                }
            }
            schedule()
            while running > 0, let finished = await group.next() {
                results[finished.0] = finished.1
                running -= 1
                if !Task.isCancelled {
                    schedule()
                }
            }
        }

        var cancelled = Task.isCancelled
        if nextIndex < moves.count {
            cancelled = true
            for index in nextIndex..<moves.count {
                results[index] = result(
                    moves[index].snapshot.url,
                    nil,
                    .skipped,
                    OrganizeMessage.cancelled,
                    id: moves[index].id
                )
            }
        }
        let finished = results.enumerated().map { index, item in
            item ?? result(moves[index].snapshot.url, nil, .skipped, OrganizeMessage.cancelled, id: moves[index].id)
        }
        return BatchResult(batchID: batchID, results: finished, cancelled: cancelled)
    }

    private func executeOne(
        _ move: PlannedMove,
        batchID: UUID,
        sourceRoot: URL,
        replaceConfirmed: Bool,
        claims: DestinationClaims
    ) async -> FileMoveResult {
        if Task.isCancelled {
            let outcome = result(move.snapshot.url, nil, .skipped, OrganizeMessage.cancelled, id: move.id)
            await remember(move, batchID: batchID, id: move.id, result: outcome, trashedPath: nil)
            return outcome
        }
        let decision = await claims.prepare(move, sourceRoot: sourceRoot, replaceConfirmed: replaceConfirmed)
        switch decision {
        case .stop(let outcome):
            await remember(move, batchID: batchID, id: move.id, result: outcome, trashedPath: nil)
            return outcome
        case .commit(let commit):
            let entry = JournalEntry(
                batchID: batchID,
                sourcePath: move.snapshot.url.path,
                destinationPath: commit.destination.path,
                originalName: move.snapshot.name,
                finalName: commit.destination.lastPathComponent,
                categoryName: move.categoryName,
                categoryID: move.categoryID,
                status: .pending
            )
            if let journal {
                do {
                    try await journal.appendPending(entry)
                } catch {
                    CoreLog.organizer.error("Journal pending write failed: \(error.localizedDescription, privacy: .public)")
                    return result(move.snapshot.url, nil, .failed, OrganizeMessage.journalFailed, id: move.id)
                }
            }
            let applied = apply(commit, move: move)
            if let journal {
                do {
                    try await journal.markDone(
                        id: entry.id,
                        status: applied.result.status,
                        finalName: applied.result.destinationURL?.lastPathComponent ?? commit.destination.lastPathComponent,
                        message: applied.result.message,
                        trashedPath: applied.trashedPath
                    )
                } catch {
                    CoreLog.organizer.error("Journal completion write failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            await remember(move, batchID: batchID, id: entry.id, result: applied.result, trashedPath: applied.trashedPath)
            return applied.result
        }
    }

    private func remember(
        _ move: PlannedMove,
        batchID: UUID,
        id: UUID,
        result: FileMoveResult,
        trashedPath: String?
    ) async {
        guard let history else { return }
        let destination = result.destinationURL
        let item = HistoryItem(
            id: id,
            batchID: batchID,
            createdAt: Date(),
            sourcePath: move.snapshot.url.path,
            destinationPath: destination?.path ?? move.proposedURL.path,
            originalName: move.snapshot.name,
            finalName: destination?.lastPathComponent ?? move.snapshot.name,
            categoryName: move.categoryName,
            categoryID: move.categoryID,
            ruleSummary: move.ruleSummary,
            status: result.status,
            message: result.message,
            undoable: result.status == .success && destination != nil,
            fileID: move.snapshot.fileID ?? "",
            trashedReplacementPath: trashedPath
        )
        do {
            try await history.record(item)
        } catch {
            CoreLog.organizer.error("History write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ commit: Commit, move: PlannedMove) -> (result: FileMoveResult, trashedPath: String?) {
        var trashedPath: String?
        do {
            try fileSystem.createDirectory(at: commit.directory)
            if let existing = commit.trashURL {
                trashedPath = try fileSystem.trashItem(at: existing).path
            }
            if DestinationPath.sameFile(commit.destination, move.snapshot.url) {
                return (result(move.snapshot.url, commit.destination, .skipped, OrganizeMessage.alreadyThere, id: move.id), trashedPath)
            }
            try fileSystem.moveItem(at: move.snapshot.url, to: commit.destination)
            let message = commit.trashURL == nil ? OrganizeMessage.moved : OrganizeMessage.replaced
            return (result(move.snapshot.url, commit.destination, .success, message, id: move.id), trashedPath)
        } catch {
            return (result(move.snapshot.url, commit.destination, .failed, error.localizedDescription, id: move.id), trashedPath)
        }
    }

    public func organize(_ requests: [FileOrganizationRequest], sourceRoot: URL) -> [FileMoveResult] {
        requests.map { organizeOne($0, sourceRoot: sourceRoot) }
    }

    private func organizeOne(_ request: FileOrganizationRequest, sourceRoot: URL) -> FileMoveResult {
        let snapshot = request.snapshot
        if snapshot.isSymlink {
            return result(snapshot.url, nil, .skipped, "Links are not moved")
        }
        if snapshot.isDirectory && !snapshot.isPackage {
            return result(snapshot.url, nil, .skipped, "Folders are not moved")
        }
        guard fileSystem.fileExists(at: snapshot.url) else {
            return result(snapshot.url, nil, .skipped, "File disappeared before it could be moved")
        }
        if DestinationPath.escapesSource(request.category.destination) {
            return result(snapshot.url, nil, .failed, "Destination is outside the source folder")
        }

        let directory = DestinationPath.directory(for: request.category.destination, sourceRoot: sourceRoot)
        do {
            try fileSystem.createDirectory(at: directory)
            let destination = try uniqueURL(in: directory, fileName: snapshot.name, ignoring: snapshot.url)
            if destination.standardizedFileURL == snapshot.url.standardizedFileURL {
                return result(snapshot.url, destination, .skipped, "File is already at the destination")
            }
            try fileSystem.moveItem(at: snapshot.url, to: destination)
            return result(snapshot.url, destination, .success, "Moved")
        } catch {
            return result(snapshot.url, nil, .failed, error.localizedDescription)
        }
    }

    private func uniqueURL(in directory: URL, fileName: String, ignoring source: URL) throws -> URL {
        if !isTaken(candidate(directory, fileName: fileName, index: nil), ignoring: source) {
            return candidate(directory, fileName: fileName, index: nil)
        }
        var index = 1
        while index <= 10_000 {
            let url = candidate(directory, fileName: fileName, index: index)
            if !isTaken(url, ignoring: source) {
                return url
            }
            index += 1
        }
        throw OrganizerError.tooManyNameCollisions
    }

    private func candidate(_ directory: URL, fileName: String, index: Int?) -> URL {
        directory.appendingPathComponent(Self.renamed(fileName, index: index))
    }

    static func renamed(_ fileName: String, index: Int?) -> String {
        guard let index else { return fileName }
        let ext = URL(fileURLWithPath: fileName).pathExtension
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if ext.isEmpty {
            return "\(base) (\(index))"
        }
        return "\(base) (\(index)).\(ext)"
    }

    private func isTaken(_ url: URL, ignoring source: URL) -> Bool {
        if url.standardizedFileURL == source.standardizedFileURL {
            return false
        }
        return fileSystem.fileExists(at: url)
    }

    private func result(
        _ source: URL,
        _ destination: URL?,
        _ status: OperationStatus,
        _ message: String,
        id: UUID? = nil
    ) -> FileMoveResult {
        FileMoveResult(sourceURL: source, destinationURL: destination, status: status, message: message, plannedMoveID: id)
    }
}

private struct Commit: Sendable {
    var directory: URL
    var destination: URL
    var trashURL: URL?
}

private enum MoveDecision: Sendable {
    case stop(FileMoveResult)
    case commit(Commit)
}

private actor DestinationClaims {
    private var reserved: Set<String> = []
    private let fileSystem: any FileSystemProviding
    private let resolver: ConflictResolver

    init(fileSystem: any FileSystemProviding, resolver: ConflictResolver) {
        self.fileSystem = fileSystem
        self.resolver = resolver
    }

    func prepare(_ move: PlannedMove, sourceRoot: URL, replaceConfirmed: Bool) -> MoveDecision {
        if move.predictedStatus == .failed || move.action == .blocked {
            return .stop(Self.outcome(move, status: .failed, message: move.message))
        }
        if move.action == .skip || move.predictedStatus == .skipped {
            return .stop(Self.outcome(move, status: .skipped, message: move.message))
        }
        if move.action == .needsDecision {
            return .stop(Self.outcome(move, status: .needsDecision, message: move.message))
        }
        if let stopped = restat(move) {
            return .stop(stopped)
        }
        let resolution = resolver.resolve(
            source: move.snapshot.url,
            directory: move.destinationDirectory,
            fileName: move.snapshot.name,
            policy: move.policy,
            existsOnDisk: { [fileSystem] url in
                !DestinationPath.sameFile(url, move.snapshot.url) && fileSystem.fileExists(at: url)
            },
            isReserved: { [reserved] url in
                reserved.contains(url.standardizedFileURL.path)
            }
        )
        switch resolution {
        case .skip(let message):
            return .stop(Self.outcome(move, status: .skipped, message: message))
        case .needsDecision:
            return .stop(Self.outcome(move, status: .needsDecision, message: OrganizeMessage.needsDecision))
        case .replace(let url):
            guard replaceConfirmed else {
                return .stop(Self.outcome(move, status: .needsDecision, message: OrganizeMessage.replaceNeedsConfirmation))
            }
            reserved.insert(url.standardizedFileURL.path)
            return .commit(Commit(directory: move.destinationDirectory, destination: url, trashURL: url))
        case .ready(let url, _):
            reserved.insert(url.standardizedFileURL.path)
            return .commit(Commit(directory: move.destinationDirectory, destination: url, trashURL: nil))
        }
    }

    private func restat(_ move: PlannedMove) -> FileMoveResult? {
        guard fileSystem.fileExists(at: move.snapshot.url) else {
            return Self.outcome(move, status: .skipped, message: OrganizeMessage.disappeared)
        }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let attributes: FileAttributes
        do {
            attributes = try fileSystem.attributes(of: move.snapshot.url, keys: keys)
        } catch {
            return Self.outcome(move, status: .skipped, message: OrganizeMessage.disappeared)
        }
        if let expected = move.snapshot.modified, let actual = attributes.modified, expected != actual {
            return Self.outcome(move, status: .skipped, message: OrganizeMessage.changed)
        }
        if move.snapshot.size != attributes.size {
            return Self.outcome(move, status: .skipped, message: OrganizeMessage.changed)
        }
        return nil
    }

    private static func outcome(_ move: PlannedMove, status: OperationStatus, message: String) -> FileMoveResult {
        FileMoveResult(
            sourceURL: move.snapshot.url,
            destinationURL: nil,
            status: status,
            message: message,
            plannedMoveID: move.id
        )
    }
}

private actor ProgressCounter {
    private var completed = 0
    private let total: Int
    private let continuation: AsyncStream<OrganizeProgress>.Continuation

    init(total: Int, continuation: AsyncStream<OrganizeProgress>.Continuation) {
        self.total = total
        self.continuation = continuation
    }

    func finishOne(fileName: String) {
        completed += 1
        continuation.yield(OrganizeProgress(completed: completed, total: total, fileName: fileName))
    }
}

private enum OrganizerError: LocalizedError {
    case tooManyNameCollisions

    var errorDescription: String? {
        "Too many files already use this name"
    }
}
