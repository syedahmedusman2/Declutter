import Foundation

public struct RuleIssue: Sendable, Equatable, Identifiable {
    public var conditionID: UUID
    public var message: String

    public var id: UUID { conditionID }

    public init(conditionID: UUID, message: String) {
        self.conditionID = conditionID
        self.message = message
    }
}

public enum RuleValidator {
    /// `nil` when the pattern compiles. The editor shows the message inline and refuses to save.
    public static func regexError(pattern: String) -> String? {
        do {
            _ = try compile(pattern, matchCase: false)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func issues(in node: RuleNode) -> [RuleIssue] {
        switch node {
        case .group(_, let children):
            return children.flatMap { issues(in: $0) }
        case .condition(let condition):
            guard condition.field == .filename, condition.op == .regex else { return [] }
            let pattern = condition.value ?? ""
            guard let message = regexError(pattern: pattern) else { return [] }
            return [RuleIssue(conditionID: condition.id, message: message)]
        }
    }

    static func compile(_ pattern: String, matchCase: Bool) throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if !matchCase {
            options.insert(.caseInsensitive)
        }
        return try NSRegularExpression(pattern: pattern, options: options)
    }
}
