import Foundation

public enum Destination: Codable, Sendable, Equatable {
    case relative(String)
    case absolute(path: String, bookmark: Data?)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case bookmark
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "relative":
            self = .relative(try container.decode(String.self, forKey: .path))
        case "absolute":
            let path = try container.decode(String.self, forKey: .path)
            let bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
            self = .absolute(path: path, bookmark: bookmark)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown destination type \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .relative(let path):
            try container.encode("relative", forKey: .type)
            try container.encode(path, forKey: .path)
        case .absolute(let path, let bookmark):
            try container.encode("absolute", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(bookmark, forKey: .bookmark)
        }
    }
}

extension Destination {
    public var path: String {
        switch self {
        case .relative(let path):
            path
        case .absolute(let path, _):
            path
        }
    }

    public var isAbsolute: Bool {
        if case .absolute = self { return true }
        return false
    }
}

public enum ConflictPolicy: String, Codable, Sendable, Equatable, Hashable {
    case ask
    case autoRename
    case skip
    case replace
}

public enum FileAction: String, Codable, Sendable, Equatable {
    case move
}

public struct Category: Identifiable, Codable, Sendable, Equatable {
    public var schemaVersion: Int = SchemaVersion.current
    public var id: UUID
    public var name: String
    public var iconSymbol: String
    public var destination: Destination
    public var enabled: Bool
    public var priority: Int
    public var rule: RuleNode
    public var conflictPolicy: ConflictPolicy?
    public var action: FileAction
    public var isCatchAll: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        iconSymbol: String,
        destination: Destination,
        enabled: Bool,
        priority: Int,
        rule: RuleNode,
        conflictPolicy: ConflictPolicy? = nil,
        action: FileAction = .move,
        isCatchAll: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.destination = destination
        self.enabled = enabled
        self.priority = priority
        self.rule = rule
        self.conflictPolicy = conflictPolicy
        self.action = action
        self.isCatchAll = isCatchAll
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
