import Foundation

public enum RuleSummary {
    public static func text(for node: RuleNode) -> String {
        switch node {
        case .condition(let condition):
            text(for: condition)
        case .group(let op, let children):
            text(op: op, childTexts: children.map { text(for: $0) })
        }
    }

    public static func text(op: LogicalOp, childTexts: [String]) -> String {
        if childTexts.isEmpty {
            switch op {
            case .and, .not:
                return "any file"
            case .or:
                return "no file"
            }
        }
        let parts = childTexts.map { child -> String in
            if child.contains(" AND ") || child.contains(" OR ") || child.hasPrefix("NOT ") {
                return "(\(child))"
            }
            return child
        }
        switch op {
        case .and:
            return parts.joined(separator: " AND ")
        case .or:
            return parts.joined(separator: " OR ")
        case .not:
            if parts.count == 1 { return "NOT \(parts[0])" }
            return "NOT (\(parts.joined(separator: " OR ")))"
        }
    }

    public static func text(for condition: Condition) -> String {
        let single = display(condition.value)
        let list = condition.values.map(display).joined(separator: ", ")
        let bounds = RuleValueParsing.list(value: condition.value, values: condition.values)
        let low = bounds.count >= 1 ? display(bounds[0]) : "?"
        let high = bounds.count >= 2 ? display(bounds[1]) : "?"
        switch (condition.field, condition.op) {
        case (.extension_, .is):
            return "Extension is \(single)"
        case (.extension_, .isNot):
            return "Extension is not \(single)"
        case (.extension_, .isOneOf):
            return "Extension is one of \(list)"
        case (.filename, .contains):
            return "Filename contains \(single)"
        case (.filename, .notContains):
            return "Filename does not contain \(single)"
        case (.filename, .startsWith):
            return "Filename starts with \(single)"
        case (.filename, .endsWith):
            return "Filename ends with \(single)"
        case (.filename, .equals):
            return "Filename equals \(single)"
        case (.filename, .notEquals):
            return "Filename does not equal \(single)"
        case (.filename, .regex):
            return "Filename matches regex \(single)"
        case (.fileType, .conformsTo):
            return "Type conforms to \(single)"
        case (.fileType, .is):
            return "Type is \(single)"
        case (.size, .greaterThan):
            return "Size is greater than \(single)"
        case (.size, .lessThan):
            return "Size is less than \(single)"
        case (.size, .equals):
            return "Size equals \(single)"
        case (.size, .between):
            return "Size is between \(low) and \(high)"
        case (.createdDate, .before):
            return "Created before \(single)"
        case (.createdDate, .after):
            return "Created after \(single)"
        case (.createdDate, .between):
            return "Created between \(low) and \(high)"
        case (.modifiedDate, .before):
            return "Modified before \(single)"
        case (.modifiedDate, .after):
            return "Modified after \(single)"
        case (.modifiedDate, .between):
            return "Modified between \(low) and \(high)"
        default:
            return "\(condition.field.rawValue) \(condition.op.rawValue)"
        }
    }

    public static func listSummary(for category: Category) -> String {
        if category.isCatchAll { return "Catch-all" }
        return text(for: category.rule)
    }

    private static func display(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "(empty)" : trimmed
    }
}
