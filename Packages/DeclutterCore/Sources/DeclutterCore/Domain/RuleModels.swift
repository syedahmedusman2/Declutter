import Foundation

public enum LogicalOp: String, Codable, Sendable, Equatable, Hashable {
    case and
    case or
    case not
}

public enum Field: String, Codable, Sendable, Equatable, Hashable {
    case extension_ = "extension"
    case filename
    case fileType
    case size
    case createdDate
    case modifiedDate

    /// Operators the rule editor offers for this field. Evaluation rejects anything else.
    public var supportedOperators: [Operator] {
        switch self {
        case .extension_:
            [.is, .isNot, .isOneOf]
        case .filename:
            [.contains, .notContains, .startsWith, .endsWith, .equals, .notEquals, .regex]
        case .fileType:
            [.conformsTo, .is]
        case .size:
            [.greaterThan, .lessThan, .equals, .between]
        case .createdDate, .modifiedDate:
            [.before, .after, .between]
        }
    }
}

public enum Operator: String, Codable, Sendable, Equatable, Hashable {
    case `is`
    case isNot
    case isOneOf
    case contains
    case notContains
    case startsWith
    case endsWith
    case equals
    case notEquals
    case regex
    case conformsTo
    case greaterThan
    case lessThan
    case between
    case before
    case after
}

public struct Condition: Identifiable, Codable, Sendable, Equatable {
    public var schemaVersion: Int = SchemaVersion.current
    public var id: UUID
    public var field: Field
    public var op: Operator
    public var value: String?
    public var values: [String]
    public var matchCase: Bool

    public init(
        id: UUID = UUID(),
        field: Field,
        op: Operator,
        value: String? = nil,
        values: [String] = [],
        matchCase: Bool = false
    ) {
        self.id = id
        self.field = field
        self.op = op
        self.value = value
        self.values = values
        self.matchCase = matchCase
    }
}

public indirect enum RuleNode: Codable, Sendable, Equatable {
    case group(LogicalOp, [RuleNode])
    case condition(Condition)

    private enum CodingKeys: String, CodingKey {
        case type
        case op
        case children
        case condition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "group":
            let op = try container.decode(LogicalOp.self, forKey: .op)
            let children = try container.decode([RuleNode].self, forKey: .children)
            self = .group(op, children)
        case "condition":
            self = .condition(try container.decode(Condition.self, forKey: .condition))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown rule node type \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .group(let op, let children):
            try container.encode("group", forKey: .type)
            try container.encode(op, forKey: .op)
            try container.encode(children, forKey: .children)
        case .condition(let condition):
            try container.encode("condition", forKey: .type)
            try container.encode(condition, forKey: .condition)
        }
    }
}
