import Foundation

public enum MonitorState: String, Codable, Sendable, Equatable {
    case stopped
    case monitoring
    case paused
    case permissionRequired
    case error
}

public struct BaselineRecord: Codable, Sendable, Equatable, Identifiable {
    public var schemaVersion: Int = SchemaVersion.current
    public var id: String
    public var path: String
    public var fileID: String?

    public init(path: String, fileID: String?) {
        self.path = path
        self.fileID = fileID
        self.id = fileID ?? path
    }
}

public struct BaselineStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [BaselineRecord] {
        guard let data = try AtomicFile.read(fileURL) else { return [] }
        let document = try JSONDecoder().decode(BaselineDocument.self, from: data)
        return document.records
    }

    public func save(_ records: [BaselineRecord]) throws {
        let document = BaselineDocument(schemaVersion: SchemaVersion.current, records: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(document), to: fileURL)
    }

    public static func contains(_ snapshot: FileSnapshot, in records: [BaselineRecord]) -> Bool {
        if let fileID = snapshot.fileID {
            return records.contains { $0.fileID == fileID }
        }
        let path = snapshot.url.standardizedFileURL.path
        return records.contains { URL(fileURLWithPath: $0.path).standardizedFileURL.path == path }
    }
}

public struct MonitorSession: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var lastEventID: UInt64?
    public var resumeState: MonitorState
    public var sourceID: UUID?
    public var mode: AutomationMode?

    public init(
        schemaVersion: Int = SchemaVersion.current,
        lastEventID: UInt64?,
        resumeState: MonitorState,
        sourceID: UUID?,
        mode: AutomationMode?
    ) {
        self.schemaVersion = schemaVersion
        self.lastEventID = lastEventID
        self.resumeState = resumeState
        self.sourceID = sourceID
        self.mode = mode
    }
}

public struct MonitorSessionStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> MonitorSession? {
        guard let data = try AtomicFile.read(fileURL) else { return nil }
        return try JSONDecoder().decode(MonitorSession.self, from: data)
    }

    public func save(_ session: MonitorSession) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(session), to: fileURL)
    }
}

struct BaselineDocument: Codable, Sendable, Equatable {
    var schemaVersion: Int
    var records: [BaselineRecord]
}

enum AtomicFile {
    static func read(_ fileURL: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    static func write(_ data: Data, to fileURL: URL) throws {
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
