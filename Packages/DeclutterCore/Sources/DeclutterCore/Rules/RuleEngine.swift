import Foundation
import UniformTypeIdentifiers

public struct RuleEngine: Sendable {
    public init() {}

    public func evaluate(_ node: RuleNode, file: FileSnapshot) -> RuleResult {
        switch node {
        case .group(let op, let children):
            let evaluated = children.map { evaluate($0, file: file) }
            let passed: Bool
            switch op {
            case .and:
                passed = evaluated.allSatisfy(\.passed)
            case .or:
                passed = evaluated.contains(where: \.passed)
            case .not:
                // One child is inverted. Several children are NOR: the group passes only when every child fails.
                passed = !evaluated.contains(where: \.passed)
            }
            return RuleResult(
                passed: passed,
                description: RuleSummary.text(op: op, childTexts: evaluated.map(\.description)),
                actualValue: "",
                children: evaluated,
                warning: nil,
                kind: .group
            )
        case .condition(let condition):
            return evaluate(condition, file: file)
        }
    }

    private func evaluate(_ condition: Condition, file: FileSnapshot) -> RuleResult {
        let description = RuleSummary.text(for: condition)
        let actual = actualValue(for: condition.field, file: file)
        guard condition.field.supportedOperators.contains(condition.op) else {
            return leaf(passed: false, description: description, actual: actual, warning: nil)
        }
        switch condition.field {
        case .extension_:
            return evaluateExtension(condition, file: file, description: description, actual: actual)
        case .filename:
            return evaluateFilename(condition, file: file, description: description, actual: actual)
        case .fileType:
            return evaluateFileType(condition, file: file, description: description, actual: actual)
        case .size:
            return evaluateSize(condition, file: file, description: description, actual: actual)
        case .createdDate, .modifiedDate:
            return evaluateDate(condition, file: file, description: description, actual: actual)
        }
    }

    private func evaluateExtension(
        _ condition: Condition,
        file: FileSnapshot,
        description: String,
        actual: String
    ) -> RuleResult {
        let foldedActual = fold(file.ext, matchCase: condition.matchCase)
        let passed: Bool
        switch condition.op {
        case .is:
            passed = foldedActual == fold(stripDot(condition.value ?? ""), matchCase: condition.matchCase)
        case .isNot:
            passed = foldedActual != fold(stripDot(condition.value ?? ""), matchCase: condition.matchCase)
        case .isOneOf:
            let expected = Set(condition.values.map { fold(stripDot($0), matchCase: condition.matchCase) })
            passed = expected.contains(foldedActual)
        default:
            passed = false
        }
        return leaf(passed: passed, description: description, actual: actual, warning: nil)
    }

    private func evaluateFilename(
        _ condition: Condition,
        file: FileSnapshot,
        description: String,
        actual: String
    ) -> RuleResult {
        let name = file.nameWithoutExt
        if condition.op == .regex {
            let pattern = condition.value ?? ""
            do {
                let expression = try RuleValidator.compile(pattern, matchCase: condition.matchCase)
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                let passed = expression.firstMatch(in: name, options: [], range: range) != nil
                return leaf(passed: passed, description: description, actual: actual, warning: nil)
            } catch {
                let message = "Invalid regular expression"
                CoreLog.rules.warning(
                    "Invalid regular expression \(pattern, privacy: .private): \(error.localizedDescription, privacy: .public)"
                )
                return leaf(passed: false, description: description, actual: actual, warning: message)
            }
        }

        let expected = condition.value ?? ""
        let passed: Bool
        switch condition.op {
        case .contains:
            passed = fold(name, matchCase: condition.matchCase).contains(fold(expected, matchCase: condition.matchCase))
        case .notContains:
            passed = !fold(name, matchCase: condition.matchCase).contains(fold(expected, matchCase: condition.matchCase))
        case .startsWith:
            passed = fold(name, matchCase: condition.matchCase).hasPrefix(fold(expected, matchCase: condition.matchCase))
        case .endsWith:
            passed = fold(name, matchCase: condition.matchCase).hasSuffix(fold(expected, matchCase: condition.matchCase))
        case .equals:
            passed = fold(name, matchCase: condition.matchCase) == fold(expected, matchCase: condition.matchCase)
        case .notEquals:
            passed = fold(name, matchCase: condition.matchCase) != fold(expected, matchCase: condition.matchCase)
        default:
            passed = false
        }
        return leaf(passed: passed, description: description, actual: actual, warning: nil)
    }

    private func evaluateFileType(
        _ condition: Condition,
        file: FileSnapshot,
        description: String,
        actual: String
    ) -> RuleResult {
        guard let expected = resolveType(condition.value ?? "", matchCase: condition.matchCase) else {
            return leaf(passed: false, description: description, actual: actual, warning: nil)
        }
        let types = fileTypes(for: file)
        let passed: Bool
        switch condition.op {
        case .is:
            passed = types.contains { identifiersMatch($0.identifier, expected.identifier, matchCase: condition.matchCase) }
        case .conformsTo:
            passed = types.contains { type in
                type.conforms(to: expected)
                    || identifiersMatch(type.identifier, expected.identifier, matchCase: condition.matchCase)
            }
        default:
            passed = false
        }
        return leaf(passed: passed, description: description, actual: actual, warning: nil)
    }

    private func evaluateSize(
        _ condition: Condition,
        file: FileSnapshot,
        description: String,
        actual: String
    ) -> RuleResult {
        let passed: Bool
        switch condition.op {
        case .greaterThan:
            guard let threshold = RuleValueParsing.integer(from: condition.value) else {
                return leaf(passed: false, description: description, actual: actual, warning: nil)
            }
            passed = file.size > threshold
        case .lessThan:
            guard let threshold = RuleValueParsing.integer(from: condition.value) else {
                return leaf(passed: false, description: description, actual: actual, warning: nil)
            }
            passed = file.size < threshold
        case .equals:
            guard let threshold = RuleValueParsing.integer(from: condition.value) else {
                return leaf(passed: false, description: description, actual: actual, warning: nil)
            }
            passed = file.size == threshold
        case .between:
            guard let bounds = RuleValueParsing.integerBounds(value: condition.value, values: condition.values) else {
                return leaf(passed: false, description: description, actual: actual, warning: nil)
            }
            passed = file.size >= bounds.low && file.size <= bounds.high
        default:
            passed = false
        }
        return leaf(passed: passed, description: description, actual: actual, warning: nil)
    }

    private func evaluateDate(
        _ condition: Condition,
        file: FileSnapshot,
        description: String,
        actual: String
    ) -> RuleResult {
        let fileDate = condition.field == .createdDate ? file.created : file.modified
        guard let fileDate else {
            return leaf(passed: false, description: description, actual: actual, warning: nil)
        }
        let passed: Bool
        switch condition.op {
        case .before:
            guard let threshold = RuleValueParsing.date(from: condition.value) else {
                return leaf(passed: false, description: description, actual: actual, warning: nil)
            }
            passed = fileDate < threshold
        case .after:
            guard let threshold = RuleValueParsing.date(from: condition.value) else {
                return leaf(passed: false, description: description, actual: actual, warning: nil)
            }
            passed = fileDate > threshold
        case .between:
            guard let bounds = RuleValueParsing.dateBounds(value: condition.value, values: condition.values) else {
                return leaf(passed: false, description: description, actual: actual, warning: nil)
            }
            passed = fileDate >= bounds.start && fileDate <= bounds.end
        default:
            passed = false
        }
        return leaf(passed: passed, description: description, actual: actual, warning: nil)
    }

    private func fileTypes(for file: FileSnapshot) -> [UTType] {
        var types: [UTType] = []
        if let identifier = file.utType, let type = UTType(identifier) {
            types.append(type)
        }
        if !file.ext.isEmpty, let type = UTType(filenameExtension: file.ext) {
            if !types.contains(where: { $0.identifier == type.identifier }) {
                types.append(type)
            }
        }
        return types
    }

    private func resolveType(_ raw: String, matchCase: Bool) -> UTType? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let type = UTType(trimmed) { return type }
        if !matchCase, let type = UTType(trimmed.lowercased()) { return type }
        let ext = stripDot(trimmed)
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: matchCase ? ext : ext.lowercased())
    }

    private func identifiersMatch(_ lhs: String, _ rhs: String, matchCase: Bool) -> Bool {
        matchCase ? lhs == rhs : lhs.lowercased() == rhs.lowercased()
    }

    private func actualValue(for field: Field, file: FileSnapshot) -> String {
        switch field {
        case .extension_:
            return file.ext.isEmpty ? "(none)" : file.ext
        case .filename:
            return file.nameWithoutExt
        case .fileType:
            if let utType = file.utType, !utType.isEmpty { return utType }
            if !file.ext.isEmpty, let derived = UTType(filenameExtension: file.ext)?.identifier {
                return derived
            }
            return "(unknown)"
        case .size:
            return String(file.size)
        case .createdDate:
            return file.created.map(RuleValueParsing.format(date:)) ?? "(none)"
        case .modifiedDate:
            return file.modified.map(RuleValueParsing.format(date:)) ?? "(none)"
        }
    }

    private func leaf(passed: Bool, description: String, actual: String, warning: String?) -> RuleResult {
        RuleResult(
            passed: passed,
            description: description,
            actualValue: actual,
            children: [],
            warning: warning,
            kind: .condition
        )
    }

    private func fold(_ value: String, matchCase: Bool) -> String {
        matchCase ? value : value.lowercased()
    }

    private func stripDot(_ value: String) -> String {
        value.hasPrefix(".") ? String(value.dropFirst()) : value
    }
}
