import Foundation

public enum CategoryMigrator {
    /// Walks `document` up to `target` with ordered steps. Production loads use `SchemaVersion.current`.
    /// The v1 → v2 step is a stub that only bumps the version until a real migration is required.
    public static func migrate(
        _ document: CategoryDocument,
        upTo target: Int = SchemaVersion.current
    ) throws -> CategoryDocument {
        var current = document
        while current.schemaVersion < target {
            current = try applyStep(from: current.schemaVersion, document: current)
        }
        return current
    }

    private static func applyStep(from version: Int, document: CategoryDocument) throws -> CategoryDocument {
        switch version {
        case 1:
            var copy = document
            copy.schemaVersion = 2
            return copy
        default:
            throw CategoryStoreError.unsupportedMigration(version)
        }
    }
}
