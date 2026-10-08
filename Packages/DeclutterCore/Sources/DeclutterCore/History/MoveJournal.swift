import Foundation

public struct JournalEntry: Identifiable, Codable, Sendable, Equatable {
    public var schemaVersion: Int = SchemaVersion.current
    public var id: UUID
    public var batchID: UUID
    public var sourcePath: String
    public var destinationPath: String
    public var originalName: String
    public var finalName: String
    public var categoryName: String
    public var categoryID: UUID?
    public var status: OperationStatus
    public var message: String?
    public var trashedReplacementPath: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        batchID: UUID,
        sourcePath: String,
        destinationPath: String,
        originalName: String,
        finalName: String,
        categoryName: String,
        categoryID: UUID?,
        status: OperationStatus,
        message: String? = nil,
        trashedReplacementPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.batchID = batchID
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.originalName = originalName
        self.finalName = finalName
        self.categoryName = categoryName
        self.categoryID = categoryID
        self.status = status
        self.message = message
        self.trashedReplacementPath = trashedReplacementPath
        self.createdAt = createdAt
    }
}

public struct JournalDocument: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var entries: [JournalEntry]

    public init(schemaVersion: Int = SchemaVersion.current, entries: [JournalEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}

public protocol MoveJournal: Sendable {
    func appendPending(_ entry: JournalEntry) async throws
    func markDone(
        id: UUID,
        status: OperationStatus,
        finalName: String,
        message: String?,
        trashedPath: String?
    ) async throws
    func load() async throws -> [JournalEntry]
    func reconcilePending(using fileSystem: any FileSystemProviding) async throws -> Int
}

public enum JournalError: Error, Equatable, LocalizedError, Sendable {
    case unreadable
    case missingEntry

    public var errorDescription: String? {
        switch self {
        case .unreadable: "The move journal could not be read."
        case .missingEntry: "The move journal is missing an entry."
        }
    }
}

public actor FileJournal: MoveJournal {
    private let fileURL: URL
    private var document = JournalDocument(entries: [])
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func appendPending(_ entry: JournalEntry) async throws {
        try loadIfNeeded()
        var pending = entry
        pending.status = .pending
        document.entries.append(pending)
        try persist()
    }

    public func markDone(
        id: UUID,
        status: OperationStatus,
        finalName: String,
        message: String?,
        trashedPath: String?
    ) async throws {
        try loadIfNeeded()
        guard let index = document.entries.firstIndex(where: { $0.id == id }) else {
            throw JournalError.missingEntry
        }
        document.entries[index].status = status
        document.entries[index].finalName = finalName
        document.entries[index].message = message
        document.entries[index].trashedReplacementPath = trashedPath
        try persist()
    }

    public func load() async throws -> [JournalEntry] {
        try loadIfNeeded()
        return document.entries
    }

    /// Pending entries are marked success when the file is already at the destination, or failed when the move was interrupted.
    public func reconcilePending(using fileSystem: any FileSystemProviding) async throws -> Int {
        try loadIfNeeded()
        var updated = 0
        for index in document.entries.indices where document.entries[index].status == .pending {
            let entry = document.entries[index]
            let source = URL(fileURLWithPath: entry.sourcePath)
            let destination = URL(fileURLWithPath: entry.destinationPath)
            let atDestination = fileSystem.fileExists(at: destination)
            let atSource = fileSystem.fileExists(at: source)
            if atDestination && !atSource {
                document.entries[index].status = .success
                document.entries[index].message = OrganizeMessage.moved
            } else if atSource {
                document.entries[index].status = .failed
                document.entries[index].message = "interrupted"
            } else {
                document.entries[index].status = .failed
                document.entries[index].message = "missing"
            }
            updated += 1
        }
        if updated > 0 {
            try persist()
        }
        return updated
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        do {
            document = try JSONDecoder().decode(JournalDocument.self, from: data)
        } catch {
            throw JournalError.unreadable
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }
}
