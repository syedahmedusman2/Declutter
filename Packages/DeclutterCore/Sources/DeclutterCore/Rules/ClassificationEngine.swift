import Foundation

public struct ConsideredCategory: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var result: RuleResult

    public init(id: UUID, name: String, result: RuleResult) {
        self.id = id
        self.name = name
        self.result = result
    }
}

public struct RuleTestReport: Sendable, Equatable {
    public var matched: Bool
    public var applies: Bool
    public var categoryID: UUID
    public var categoryName: String
    public var destinationURL: URL
    public var explanation: MatchExplanation
    public var result: RuleResult
    public var higherPriorityWinnerID: UUID?
    public var higherPriorityWinnerName: String?
    public var higherPriority: [ConsideredCategory]

    public init(
        matched: Bool,
        applies: Bool,
        categoryID: UUID,
        categoryName: String,
        destinationURL: URL,
        explanation: MatchExplanation,
        result: RuleResult,
        higherPriorityWinnerID: UUID?,
        higherPriorityWinnerName: String?,
        higherPriority: [ConsideredCategory]
    ) {
        self.matched = matched
        self.applies = applies
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.destinationURL = destinationURL
        self.explanation = explanation
        self.result = result
        self.higherPriorityWinnerID = higherPriorityWinnerID
        self.higherPriorityWinnerName = higherPriorityWinnerName
        self.higherPriority = higherPriority
    }
}

public struct ClassificationEngine: Sendable {
    private let categories: [Category]
    private let rules = RuleEngine()

    public init(categories: [Category]) {
        self.categories = categories
    }

    /// Enabled categories run in ascending priority. The first matching rule wins. Catch-all categories run only after that.
    public func classify(_ file: FileSnapshot, sourceRoot: URL) -> Classification? {
        for category in orderedSpecific() where category.enabled {
            let result = rules.evaluate(category.rule, file: file)
            if result.passed {
                return makeClassification(category, file: file, sourceRoot: sourceRoot, result: result, summary: result.description)
            }
        }
        guard let category = orderedCatchAll().first(where: \.enabled) else { return nil }
        let result = RuleResult(
            passed: true,
            description: "Catch-all",
            actualValue: "",
            children: [],
            warning: nil,
            kind: .group
        )
        return makeClassification(category, file: file, sourceRoot: sourceRoot, result: result, summary: "Catch-all")
    }

    /// Evaluates `category` (including an unsaved draft) and reports whether an earlier enabled category would take the file.
    public func testRule(_ category: Category, file: FileSnapshot, sourceRoot: URL) -> RuleTestReport {
        let result = rules.evaluate(category.rule, file: file)
        let earlier = categories
            .filter { other in
                other.id != category.id && other.enabled && !other.isCatchAll
                    && (category.isCatchAll || other.priority < category.priority)
            }
            .sorted(by: Self.priorityThenName)
        let considered = earlier.map { other in
            ConsideredCategory(id: other.id, name: other.name, result: rules.evaluate(other.rule, file: file))
        }
        let winner = considered.first { $0.result.passed }
        let matched = result.passed
        let applies = category.enabled && (category.isCatchAll ? winner == nil : matched && winner == nil)
        let destination = destinationURL(for: category, file: file, sourceRoot: sourceRoot)
        let summary = category.isCatchAll ? "Catch-all" : result.description
        let explanation = MatchExplanation(
            categoryID: category.id,
            categoryName: category.name,
            ruleSummary: summary,
            conditions: result.conditionResults,
            destinationURL: destination
        )
        return RuleTestReport(
            matched: matched,
            applies: applies,
            categoryID: category.id,
            categoryName: category.name,
            destinationURL: destination,
            explanation: explanation,
            result: result,
            higherPriorityWinnerID: winner?.id,
            higherPriorityWinnerName: winner?.name,
            higherPriority: considered
        )
    }

    private func makeClassification(
        _ category: Category,
        file: FileSnapshot,
        sourceRoot: URL,
        result: RuleResult,
        summary: String
    ) -> Classification {
        let explanation = MatchExplanation(
            categoryID: category.id,
            categoryName: category.name,
            ruleSummary: summary,
            conditions: result.conditionResults,
            destinationURL: destinationURL(for: category, file: file, sourceRoot: sourceRoot)
        )
        return Classification(category: category, explanation: explanation)
    }

    private func destinationURL(for category: Category, file: FileSnapshot, sourceRoot: URL) -> URL {
        DestinationPath.directory(for: category.destination, sourceRoot: sourceRoot)
            .appendingPathComponent(file.name)
    }

    private func orderedSpecific() -> [Category] {
        categories.filter { !$0.isCatchAll }.sorted(by: Self.priorityThenName)
    }

    private func orderedCatchAll() -> [Category] {
        categories.filter(\.isCatchAll).sorted(by: Self.priorityThenName)
    }

    private static func priorityThenName(_ lhs: Category, _ rhs: Category) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        return lhs.name < rhs.name
    }
}
