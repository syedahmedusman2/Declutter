import Foundation

public struct ConditionResult: Codable, Sendable, Equatable {
    public var description: String
    public var passed: Bool
    public var actualValue: String

    public init(description: String, passed: Bool, actualValue: String) {
        self.description = description
        self.passed = passed
        self.actualValue = actualValue
    }
}

public struct MatchExplanation: Codable, Sendable, Equatable {
    public var schemaVersion: Int = SchemaVersion.current
    public var categoryID: UUID
    public var categoryName: String
    public var ruleSummary: String
    public var conditions: [ConditionResult]
    public var destinationURL: URL

    public init(
        categoryID: UUID,
        categoryName: String,
        ruleSummary: String,
        conditions: [ConditionResult],
        destinationURL: URL
    ) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.ruleSummary = ruleSummary
        self.conditions = conditions
        self.destinationURL = destinationURL
    }
}

public enum OperationStatus: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case pending
    case success
    case skipped
    case failed
    case undone
    case needsDecision
}

public struct Classification: Sendable, Equatable {
    public var category: Category
    public var explanation: MatchExplanation

    public init(category: Category, explanation: MatchExplanation) {
        self.category = category
        self.explanation = explanation
    }
}

public enum RuleResultKind: String, Sendable, Equatable {
    case group
    case condition
}

/// Pass/fail tree for one rule evaluation. Groups keep their children so the UI can show ✓/✗ at each node.
public struct RuleResult: Sendable, Equatable {
    public var passed: Bool
    public var description: String
    public var actualValue: String
    public var children: [RuleResult]
    public var warning: String?
    public var kind: RuleResultKind

    public init(
        passed: Bool,
        description: String,
        actualValue: String,
        children: [RuleResult],
        warning: String?,
        kind: RuleResultKind
    ) {
        self.passed = passed
        self.description = description
        self.actualValue = actualValue
        self.children = children
        self.warning = warning
        self.kind = kind
    }

    public var conditionResults: [ConditionResult] {
        switch kind {
        case .condition:
            [ConditionResult(description: description, passed: passed, actualValue: actualValue)]
        case .group:
            children.flatMap(\.conditionResults)
        }
    }

    public var warnings: [String] {
        var collected: [String] = []
        if let warning, !warning.isEmpty {
            collected.append(warning)
        }
        collected.append(contentsOf: children.flatMap(\.warnings))
        return collected
    }
}
