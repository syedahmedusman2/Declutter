import Foundation

public enum SourceFolderStoreError: Error, Equatable, LocalizedError, Sendable {
    case newerSchema(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case .newerSchema(let found, let supported):
            "This folder was saved by a newer version of the app (schema \(found); this app supports \(supported))."
        }
    }
}

public struct SourceFolderFileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> SourceFolder? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let folder = try JSONDecoder().decode(SourceFolder.self, from: data)
        guard folder.schemaVersion <= SchemaVersion.current else {
            throw SourceFolderStoreError.newerSchema(found: folder.schemaVersion, supported: SchemaVersion.current)
        }
        return folder
    }

    public func save(_ folder: SourceFolder) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(folder)
        try data.write(to: fileURL, options: .atomic)
    }
}
