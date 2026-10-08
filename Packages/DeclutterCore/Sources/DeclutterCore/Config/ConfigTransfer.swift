import Foundation

public struct ConfigSettingsSnapshot: Codable, Sendable, Equatable {
    public var runInBackground: Bool
    public var showMenuBarIcon: Bool
    public var showInDock: Bool
    public var resumeMonitoringOnLaunch: Bool
    public var automationMode: String
    public var historyRetentionDays: Int
    public var removeEmptyFolders: Bool

    public init(
        runInBackground: Bool,
        showMenuBarIcon: Bool,
        showInDock: Bool,
        resumeMonitoringOnLaunch: Bool,
        automationMode: String,
        historyRetentionDays: Int,
        removeEmptyFolders: Bool
    ) {
        self.runInBackground = runInBackground
        self.showMenuBarIcon = showMenuBarIcon
        self.showInDock = showInDock
        self.resumeMonitoringOnLaunch = resumeMonitoringOnLaunch
        self.automationMode = automationMode
        self.historyRetentionDays = historyRetentionDays
        self.removeEmptyFolders = removeEmptyFolders
    }
}

public struct ImportPreview: Sendable, Equatable {
    public var added: [String]
    public var removed: [String]
    public var changed: [String]
    public var warnings: [String]
    public var categories: [Category]
    public var settings: ConfigSettingsSnapshot

    public init(
        added: [String],
        removed: [String],
        changed: [String],
        warnings: [String],
        categories: [Category],
        settings: ConfigSettingsSnapshot
    ) {
        self.added = added
        self.removed = removed
        self.changed = changed
        self.warnings = warnings
        self.categories = categories
        self.settings = settings
    }
}

public enum ConfigTransferError: Error, Equatable, LocalizedError, Sendable {
    case malformed
    case wrongFormat
    case newerSchema(Int)
    case invalidRules([String])
    case unsafeDestination(String)

    public var errorDescription: String? {
        switch self {
        case .malformed:
            "The file is not a valid configuration."
        case .wrongFormat:
            "This file is not a Declutter configuration."
        case .newerSchema(let version):
            "This configuration uses schema \(version), which is newer than this version of the app."
        case .invalidRules(let messages):
            messages.joined(separator: " ")
        case .unsafeDestination(let name):
            "\(name) has a destination that leaves the folder."
        }
    }
}

public enum ConfigTransfer {
    public static let format = "declutter-config"

    public static func export(
        categories: [Category],
        settings: ConfigSettingsSnapshot,
        now: Date = Date()
    ) throws -> Data {
        let envelope = Envelope(
            format: format,
            schemaVersion: SchemaVersion.current,
            exportedAt: now,
            settings: settings,
            categories: categories.map(stripped)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    public static func validate(_ data: Data, current: [Category]) throws -> ImportPreview {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw ConfigTransferError.malformed
        }
        guard header.format == format || header.format == "download-organizer-config" else { throw ConfigTransferError.wrongFormat }
        if header.schemaVersion > SchemaVersion.current {
            throw ConfigTransferError.newerSchema(header.schemaVersion)
        }
        if header.schemaVersion < 1 {
            throw ConfigTransferError.malformed
        }
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw ConfigTransferError.malformed
        }
        var categories = envelope.categories.map(stripped)
        if header.schemaVersion < SchemaVersion.current {
            let migrated = try CategoryMigrator.migrate(
                CategoryDocument(schemaVersion: header.schemaVersion, categories: categories),
                upTo: SchemaVersion.current
            )
            categories = migrated.categories.map(stripped)
        }
        var ruleMessages: [String] = []
        for category in categories {
            if unsafe(category.destination.path) {
                throw ConfigTransferError.unsafeDestination(category.name)
            }
            ruleMessages.append(contentsOf: RuleValidator.issues(in: category.rule).map {
                "\(category.name): \($0.message)"
            })
        }
        if !ruleMessages.isEmpty {
            throw ConfigTransferError.invalidRules(ruleMessages)
        }
        let warnings = categories.compactMap { category -> String? in
            guard case .absolute = category.destination else { return nil }
            return "\(category.name) uses an absolute destination. Its bookmark was not included."
        }
        let difference = diff(current: current, imported: categories)
        return ImportPreview(
            added: difference.added,
            removed: difference.removed,
            changed: difference.changed,
            warnings: warnings,
            categories: categories,
            settings: envelope.settings
        )
    }

    public static func defaults() -> [Category] {
        DefaultCategories.make()
    }

    private static func stripped(_ category: Category) -> Category {
        var copy = category
        if case .absolute(let path, _) = copy.destination {
            copy.destination = .absolute(path: path, bookmark: nil)
        }
        return copy
    }

    private static func unsafe(_ path: String) -> Bool {
        path.split(separator: "/").contains("..")
    }

    private static func diff(
        current: [Category],
        imported: [Category]
    ) -> (added: [String], removed: [String], changed: [String]) {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var added: [String] = []
        var changed: [String] = []
        var matched = Set<UUID>()
        for category in imported {
            if let existing = currentByID[category.id] {
                matched.insert(category.id)
                let differs = existing.name != category.name
                    || existing.destination.path != category.destination.path
                    || existing.rule != category.rule
                    || existing.enabled != category.enabled
                    || existing.priority != category.priority
                    || existing.conflictPolicy != category.conflictPolicy
                if differs {
                    changed.append(category.name)
                }
            } else {
                added.append(category.name)
            }
        }
        let removed = current.filter { !matched.contains($0.id) }.map(\.name)
        return (added, removed, changed)
    }
}

private struct Header: Decodable {
    var format: String
    var schemaVersion: Int
}

private struct Envelope: Codable {
    var format: String
    var schemaVersion: Int
    var exportedAt: Date
    var settings: ConfigSettingsSnapshot
    var categories: [Category]
}
