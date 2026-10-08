import Foundation

/// The extension-chip editor reads and writes a top-level "extension is one of" condition.
/// Any other conditions stay in the advanced tree, ANDed with that extension list.
public enum RuleComposer {
    public static func primaryExtensions(in rule: RuleNode) -> [String] {
        switch rule {
        case .condition(let condition):
            return extensions(in: condition) ?? []
        case .group(.and, let children):
            guard let first = children.first, case .condition(let condition) = first else { return [] }
            return extensions(in: condition) ?? []
        case .group:
            return []
        }
    }

    public static func advancedRule(in rule: RuleNode) -> RuleNode? {
        switch rule {
        case .condition(let condition):
            return extensions(in: condition) == nil ? rule : nil
        case .group(.and, let children):
            guard let first = children.first, case .condition(let condition) = first, extensions(in: condition) != nil else {
                return rule
            }
            let rest = Array(children.dropFirst())
            if rest.isEmpty { return nil }
            if rest.count == 1 { return rest[0] }
            return .group(.and, rest)
        case .group:
            return rule
        }
    }

    public static func compose(extensions: [String], advanced: RuleNode?, catchAll: Bool) -> RuleNode {
        if catchAll {
            return .group(.and, [])
        }
        let cleaned = extensions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
        let extensionNode: RuleNode? = cleaned.isEmpty
            ? nil
            : .condition(Condition(field: .extension_, op: .isOneOf, values: cleaned, matchCase: false))
        switch (extensionNode, advanced) {
        case (nil, nil):
            return .group(.and, [])
        case (let node?, nil):
            return node
        case (nil, let node?):
            return node
        case (let ext?, let extra?):
            return .group(.and, [ext, extra])
        }
    }

    private static func extensions(in condition: Condition) -> [String]? {
        guard condition.field == .extension_ else { return nil }
        switch condition.op {
        case .is:
            let value = condition.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? [] : [value.hasPrefix(".") ? String(value.dropFirst()) : value]
        case .isOneOf:
            return condition.values
        default:
            return nil
        }
    }
}
