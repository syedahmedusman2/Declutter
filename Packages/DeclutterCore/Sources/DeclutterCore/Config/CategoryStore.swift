import Foundation

public struct CategoryDocument: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var categories: [Category]

    public init(schemaVersion: Int = SchemaVersion.current, categories: [Category]) {
        self.schemaVersion = schemaVersion
        self.categories = categories
    }
}

public struct StoredCategories: Sendable, Equatable {
    public var categories: [Category]
    public var schemaVersion: Int
    public var isReadOnly: Bool
    public var message: String?

    public init(categories: [Category], schemaVersion: Int, isReadOnly: Bool, message: String?) {
        self.categories = categories
        self.schemaVersion = schemaVersion
        self.isReadOnly = isReadOnly
        self.message = message
    }
}

public enum CategoryStoreError: Error, Equatable, LocalizedError, Sendable {
    case readOnly
    case unreadable
    case unsupportedMigration(Int)

    public var errorDescription: String? {
        switch self {
        case .readOnly:
            "This configuration was saved by a newer version and is open read-only."
        case .unreadable:
            "The category file could not be read."
        case .unsupportedMigration(let version):
            "Cannot migrate category schema version \(version)."
        }
    }
}

public struct CategoryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var backupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("config.backup.json")
    }

    public func load() throws -> StoredCategories? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let document: CategoryDocument
        do {
            document = try JSONDecoder().decode(CategoryDocument.self, from: data)
        } catch {
            throw CategoryStoreError.unreadable
        }
        if document.schemaVersion > SchemaVersion.current {
            return StoredCategories(
                categories: document.categories,
                schemaVersion: document.schemaVersion,
                isReadOnly: true,
                message: "This configuration was saved by a newer version (schema \(document.schemaVersion)). It is open read-only."
            )
        }
        let migrated = try CategoryMigrator.migrate(document)
        return StoredCategories(
            categories: migrated.categories,
            schemaVersion: migrated.schemaVersion,
            isReadOnly: false,
            message: nil
        )
    }

    /// Writes the current schema atomically. Pass the schema version returned by `load` so a newer file is not overwritten.
    public func save(_ categories: [Category], loadedSchemaVersion: Int? = nil) throws {
        if let loadedSchemaVersion, loadedSchemaVersion > SchemaVersion.current {
            throw CategoryStoreError.readOnly
        }
        let document = CategoryDocument(schemaVersion: SchemaVersion.current, categories: categories)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try writeAtomically(data)
    }

    private func writeAtomically(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }
}
