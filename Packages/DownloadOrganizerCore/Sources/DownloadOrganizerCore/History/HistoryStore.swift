import Foundation
import SwiftData

public protocol HistoryRecording: Sendable {
    func record(_ item: HistoryItem) async throws
}

public actor HistoryStore: HistoryRecording {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public static func inMemory() throws -> HistoryStore {
        let schema = Schema([HistoryRecord.self, BatchRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return HistoryStore(container: container)
    }

    public static func make(in directory: URL) -> HistoryStore {
        if let store = try? persistent(in: directory) {
            return store
        }
        do {
            return try inMemory()
        } catch {
            preconditionFailure("History store could not be created: \(error)")
        }
    }

    public static func persistent(in directory: URL) throws -> HistoryStore {
        let schema = Schema([HistoryRecord.self, BatchRecord.self])
        let url = directory.appendingPathComponent("history.store")
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return HistoryStore(container: container)
    }

    public func record(_ item: HistoryItem) throws {
        let context = ModelContext(container)
        let target = item.id
        var descriptor = FetchDescriptor<HistoryRecord>(
            predicate: #Predicate { $0.recordID == target }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.apply(item)
        } else {
            let row = HistoryRecord(
                recordID: item.id,
                batchID: item.batchID,
                createdAt: item.createdAt,
                sourcePath: item.sourcePath,
                destinationPath: item.destinationPath,
                originalName: item.originalName,
                finalName: item.finalName,
                categoryName: item.categoryName,
                categoryID: item.categoryID,
                ruleSummary: item.ruleSummary,
                statusRaw: item.status.rawValue,
                message: item.message,
                undoable: item.undoable,
                fileID: item.fileID,
                trashedReplacementPath: item.trashedReplacementPath ?? ""
            )
            context.insert(row)
            try ensureBatch(item, in: context)
        }
        try context.save()
    }

    public func query(_ query: HistoryQuery = HistoryQuery()) throws -> [HistoryItem] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<HistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try context.fetch(descriptor).map { $0.item() }.filter { item in
            if let status = query.status, item.status != status { return false }
            if let category = query.categoryName, item.categoryName != category { return false }
            if let from = query.from, item.createdAt < from { return false }
            if let to = query.to, item.createdAt > to { return false }
            if !needle.isEmpty {
                let haystack = "\(item.originalName) \(item.finalName) \(item.categoryName) \(item.message) \(item.ruleSummary)"
                    .lowercased()
                if !haystack.contains(needle) { return false }
            }
            return true
        }.prefix(query.limit).map { $0 }
    }

    public func undoableItems() throws -> [HistoryItem] {
        try query(HistoryQuery(status: .success, limit: 10_000)).filter(\.undoable)
    }

    public func items(batchID: UUID) throws -> [HistoryItem] {
        try query(HistoryQuery(limit: 10_000)).filter { $0.batchID == batchID }
    }

    public func items(ids: [UUID]) throws -> [HistoryItem] {
        let wanted = Set(ids)
        return try query(HistoryQuery(limit: 10_000)).filter { wanted.contains($0.id) }
    }

    public func markUndone(id: UUID) throws {
        let context = ModelContext(container)
        let target = id
        var descriptor = FetchDescriptor<HistoryRecord>(
            predicate: #Predicate { $0.recordID == target }
        )
        descriptor.fetchLimit = 1
        guard let row = try context.fetch(descriptor).first else { return }
        row.statusRaw = OperationStatus.undone.rawValue
        row.undoable = false
        row.message = "Undone"
        try context.save()
    }

    /// Copies reconciled journal rows into history. Existing rows keep their explanation and only take the journal outcome.
    public func importJournal(_ entries: [JournalEntry]) throws {
        let context = ModelContext(container)
        for entry in entries {
            let target = entry.id
            var descriptor = FetchDescriptor<HistoryRecord>(
                predicate: #Predicate { $0.recordID == target }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.statusRaw = entry.status.rawValue
                existing.finalName = entry.finalName
                existing.destinationPath = entry.destinationPath
                existing.undoable = entry.status == .success
                if let message = entry.message {
                    existing.message = message
                }
                if let trashed = entry.trashedReplacementPath {
                    existing.trashedReplacementPath = trashed
                }
            } else {
                let row = HistoryRecord(
                    recordID: entry.id,
                    batchID: entry.batchID,
                    createdAt: entry.createdAt,
                    sourcePath: entry.sourcePath,
                    destinationPath: entry.destinationPath,
                    originalName: entry.originalName,
                    finalName: entry.finalName,
                    categoryName: entry.categoryName,
                    categoryID: entry.categoryID,
                    ruleSummary: entry.categoryName,
                    statusRaw: entry.status.rawValue,
                    message: entry.message ?? "",
                    undoable: entry.status == .success,
                    fileID: "",
                    trashedReplacementPath: entry.trashedReplacementPath ?? ""
                )
                context.insert(row)
                try ensureBatch(
                    HistoryItem(
                        id: entry.id,
                        batchID: entry.batchID,
                        createdAt: entry.createdAt,
                        sourcePath: entry.sourcePath,
                        destinationPath: entry.destinationPath,
                        originalName: entry.originalName,
                        finalName: entry.finalName,
                        categoryName: entry.categoryName,
                        categoryID: entry.categoryID,
                        ruleSummary: entry.categoryName,
                        status: entry.status,
                        message: entry.message ?? "",
                        undoable: entry.status == .success,
                        fileID: "",
                        trashedReplacementPath: entry.trashedReplacementPath
                    ),
                    in: context
                )
            }
        }
        try context.save()
    }

    public func applyRetention(days: Int, now: Date = Date()) throws {
        guard days > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<HistoryRecord>())
        for row in rows where row.createdAt < cutoff {
            context.delete(row)
        }
        try context.save()
    }

    public func clearHistory() throws {
        let context = ModelContext(container)
        for row in try context.fetch(FetchDescriptor<HistoryRecord>()) {
            context.delete(row)
        }
        for row in try context.fetch(FetchDescriptor<BatchRecord>()) {
            context.delete(row)
        }
        try context.save()
    }

    /// Keeps the activity log and drops the ability to undo.
    public func clearUndoRecords() throws {
        let context = ModelContext(container)
        for row in try context.fetch(FetchDescriptor<HistoryRecord>()) {
            row.undoable = false
        }
        try context.save()
    }

    public func statistics(now: Date = Date(), calendar: Calendar = .current) throws -> OrganizerStatistics {
        HistoryStatistics.summarize(try query(HistoryQuery(limit: 10_000)), now: now, calendar: calendar)
    }

    private func ensureBatch(_ item: HistoryItem, in context: ModelContext) throws {
        let target = item.batchID
        var descriptor = FetchDescriptor<BatchRecord>(
            predicate: #Predicate { $0.batchID == target }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.fileCount += 1
        } else {
            context.insert(BatchRecord(batchID: item.batchID, createdAt: item.createdAt, fileCount: 1))
        }
    }
}
