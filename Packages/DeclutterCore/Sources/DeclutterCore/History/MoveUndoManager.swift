import Foundation

public enum UndoConflictChoice: Sendable {
    /// Leave the file where it is and report the occupied original path.
    case skip
    /// Move the file back beside the occupant as `name (restored).ext`.
    case renameBack
}

public struct UndoFailure: Sendable, Equatable {
    public var name: String
    public var reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

public struct UndoReport: Sendable, Equatable {
    public var succeeded: Int
    public var failed: [UndoFailure]

    public init(succeeded: Int, failed: [UndoFailure]) {
        self.succeeded = succeeded
        self.failed = failed
    }

    public static let empty = UndoReport(succeeded: 0, failed: [])
}

public struct MoveUndoManager: Sendable {
    private let fileSystem: any FileSystemProviding
    private let history: HistoryStore

    public init(fileSystem: any FileSystemProviding, history: HistoryStore) {
        self.fileSystem = fileSystem
        self.history = history
    }

    public func undoLastOperation(
        conflict: UndoConflictChoice,
        removeEmptyFolders: Bool = true
    ) async -> UndoReport {
        let items = (try? await history.undoableItems()) ?? []
        guard let latest = items.max(by: { $0.createdAt < $1.createdAt }) else {
            return .empty
        }
        return await undo(items: [latest], conflict: conflict, removeEmptyFolders: removeEmptyFolders)
    }

    public func undoLastBatch(
        conflict: UndoConflictChoice,
        removeEmptyFolders: Bool = true
    ) async -> UndoReport {
        let items = (try? await history.undoableItems()) ?? []
        guard let latest = items.max(by: { $0.createdAt < $1.createdAt }) else {
            return .empty
        }
        let batch = (try? await history.items(batchID: latest.batchID)) ?? []
        let undoable = batch.filter { $0.status == .success && $0.undoable }
        return await undo(items: undoable, conflict: conflict, removeEmptyFolders: removeEmptyFolders)
    }

    public func undo(
        ids: [UUID],
        conflict: UndoConflictChoice,
        removeEmptyFolders: Bool = true
    ) async -> UndoReport {
        let items = (try? await history.items(ids: ids)) ?? []
        let undoable = items.filter { $0.status == .success && $0.undoable }
        return await undo(items: undoable, conflict: conflict, removeEmptyFolders: removeEmptyFolders)
    }

    private func undo(
        items: [HistoryItem],
        conflict: UndoConflictChoice,
        removeEmptyFolders: Bool
    ) async -> UndoReport {
        var succeeded = 0
        var failed: [UndoFailure] = []
        let ordered = items.sorted { $0.createdAt > $1.createdAt }
        for item in ordered {
            do {
                try reverse(item, conflict: conflict, removeEmptyFolders: removeEmptyFolders)
                try await history.markUndone(id: item.id)
                succeeded += 1
            } catch let error as UndoError {
                failed.append(UndoFailure(name: item.originalName, reason: error.reason))
            } catch {
                failed.append(UndoFailure(name: item.originalName, reason: error.localizedDescription))
            }
        }
        return UndoReport(succeeded: succeeded, failed: failed)
    }

    private func reverse(
        _ item: HistoryItem,
        conflict: UndoConflictChoice,
        removeEmptyFolders: Bool
    ) throws {
        let destination = URL(fileURLWithPath: item.destinationPath)
        let source = URL(fileURLWithPath: item.sourcePath)
        guard fileSystem.fileExists(at: destination) else {
            throw UndoError(reason: "missing")
        }
        let target = try restoreTarget(source: source, conflict: conflict)
        try fileSystem.moveItem(at: destination, to: target)
        if let trashed = item.trashedReplacementPath, !trashed.isEmpty {
            let trashURL = URL(fileURLWithPath: trashed)
            if fileSystem.fileExists(at: trashURL) {
                try fileSystem.moveItem(at: trashURL, to: destination)
            }
        }
        guard removeEmptyFolders else { return }
        let folder = destination.deletingLastPathComponent()
        let sourceFolder = source.deletingLastPathComponent()
        guard folder.standardizedFileURL.path != sourceFolder.standardizedFileURL.path else { return }
        try? fileSystem.removeEmptyDirectory(at: folder)
    }

    private func restoreTarget(source: URL, conflict: UndoConflictChoice) throws -> URL {
        guard fileSystem.fileExists(at: source) else { return source }
        switch conflict {
        case .skip:
            throw UndoError(reason: "The original location is occupied")
        case .renameBack:
            let restored = restoredURL(source)
            guard !fileSystem.fileExists(at: restored) else {
                throw UndoError(reason: "The original location is occupied")
            }
            return restored
        }
    }

    private func restoredURL(_ source: URL) -> URL {
        let ext = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? "\(base) (restored)" : "\(base) (restored).\(ext)"
        return source.deletingLastPathComponent().appendingPathComponent(name)
    }
}

private struct UndoError: Error {
    var reason: String
}
