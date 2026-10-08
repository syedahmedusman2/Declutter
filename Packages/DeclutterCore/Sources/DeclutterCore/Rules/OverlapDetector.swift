import Foundation

public enum OverlapKind: String, Sendable, Equatable {
    /// The lower category cannot win: the higher one matches every file the lower one matches.
    case shadowed
    /// Both categories can match some of the same files. The higher one wins those files.
    case overlaps
}

public struct OverlapWarning: Sendable, Equatable, Identifiable {
    public var categoryID: UUID
    public var categoryName: String
    public var otherCategoryID: UUID
    public var otherCategoryName: String
    public var kind: OverlapKind
    public var message: String

    public var id: String { "\(categoryID.uuidString)-\(otherCategoryID.uuidString)-\(kind.rawValue)" }

    public init(
        categoryID: UUID,
        categoryName: String,
        otherCategoryID: UUID,
        otherCategoryName: String,
        kind: OverlapKind,
        message: String
    ) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.otherCategoryID = otherCategoryID
        self.otherCategoryName = otherCategoryName
        self.kind = kind
        self.message = message
    }
}

public struct SampleCategoryMatch: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct SampleOverlapReport: Sendable, Equatable {
    public var fileName: String
    public var matches: [SampleCategoryMatch]
    public var winnerName: String?

    public init(fileName: String, matches: [SampleCategoryMatch], winnerName: String?) {
        self.fileName = fileName
        self.matches = matches
        self.winnerName = winnerName
    }

    public var summary: String {
        guard let winnerName, !matches.isEmpty else {
            return "\(fileName) matches no category."
        }
        if matches.count == 1 {
            return "\(fileName) matches \(winnerName)."
        }
        let names = matches.map(\.name).joined(separator: ", ")
        return "\(fileName) matches \(names). \(winnerName) wins because it has higher priority."
    }
}

/// Best-effort overlap check. It compares extension sets and whether the higher rule adds narrower conditions.
/// It does not prove that two arbitrary trees are disjoint. Use `check(file:categories:)` for a real file.
public struct OverlapDetector: Sendable {
    private let rules = RuleEngine()

    public init() {}

    public func detect(categories: [Category]) -> [OverlapWarning] {
        let enabled = categories.filter { $0.enabled && !$0.isCatchAll }.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.name < rhs.name
        }
        var warnings: [OverlapWarning] = []
        for index in enabled.indices {
            for later in enabled.index(after: index)..<enabled.endIndex {
                let higher = enabled[index]
                let lower = enabled[later]
                let higherProfile = ExtensionProfile(rule: higher.rule)
                let lowerProfile = ExtensionProfile(rule: lower.rule)
                guard higherProfile.intersects(lowerProfile) else { continue }
                if higherProfile.isBroader(than: lowerProfile) {
                    warnings.append(
                        OverlapWarning(
                            categoryID: lower.id,
                            categoryName: lower.name,
                            otherCategoryID: higher.id,
                            otherCategoryName: higher.name,
                            kind: .shadowed,
                            message: "Partially shadowed by \(higher.name). \(higher.name) is broader and has higher priority, so \(lower.name) never matches."
                        )
                    )
                } else {
                    warnings.append(
                        OverlapWarning(
                            categoryID: lower.id,
                            categoryName: lower.name,
                            otherCategoryID: higher.id,
                            otherCategoryName: higher.name,
                            kind: .overlaps,
                            message: "Overlaps with \(higher.name). Some files match both; \(higher.name) wins because it has higher priority."
                        )
                    )
                }
            }
        }
        return warnings
    }

    public func check(file: FileSnapshot, categories: [Category]) -> SampleOverlapReport {
        let ordered = categories
            .filter { $0.enabled && !$0.isCatchAll }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.name < rhs.name
            }
        let matches = ordered.compactMap { category -> SampleCategoryMatch? in
            rules.evaluate(category.rule, file: file).passed
                ? SampleCategoryMatch(id: category.id, name: category.name)
                : nil
        }
        return SampleOverlapReport(fileName: file.name, matches: matches, winnerName: matches.first?.name)
    }
}

private struct ExtensionProfile: Equatable {
    /// `nil` means the rule does not restrict the extension. An empty set matches no extension.
    var extensions: Set<String>?
    var isNarrowerThanExtensions: Bool

    init(extensions: Set<String>?, isNarrowerThanExtensions: Bool) {
        self.extensions = extensions
        self.isNarrowerThanExtensions = isNarrowerThanExtensions
    }

    init(rule: RuleNode) {
        self = Self.profile(rule)
    }

    func intersects(_ other: ExtensionProfile) -> Bool {
        switch (extensions, other.extensions) {
        case (nil, _), (_, nil):
            true
        case let (lhs?, rhs?):
            !lhs.isDisjoint(with: rhs)
        }
    }

    func isBroader(than other: ExtensionProfile) -> Bool {
        guard !isNarrowerThanExtensions else { return false }
        switch (extensions, other.extensions) {
        case (nil, _):
            return true
        case let (lhs?, rhs?):
            return lhs.isSuperset(of: rhs)
        case (_?, nil):
            return false
        }
    }

    private static func profile(_ node: RuleNode) -> ExtensionProfile {
        switch node {
        case .condition(let condition):
            return conditionProfile(condition)
        case .group(let op, let children):
            let profiles = children.map(profile)
            switch op {
            case .and:
                return combineAnd(profiles)
            case .or:
                return combineOr(profiles)
            case .not:
                return ExtensionProfile(extensions: nil, isNarrowerThanExtensions: true)
            }
        }
    }

    private static func conditionProfile(_ condition: Condition) -> ExtensionProfile {
        switch (condition.field, condition.op) {
        case (.extension_, .is):
            let value = normalize(condition.value ?? "")
            return ExtensionProfile(extensions: value.isEmpty ? [] : [value], isNarrowerThanExtensions: false)
        case (.extension_, .isOneOf):
            let values = Set(condition.values.map(normalize).filter { !$0.isEmpty })
            return ExtensionProfile(extensions: values, isNarrowerThanExtensions: false)
        default:
            return ExtensionProfile(extensions: nil, isNarrowerThanExtensions: true)
        }
    }

    private static func combineAnd(_ profiles: [ExtensionProfile]) -> ExtensionProfile {
        if profiles.isEmpty {
            return ExtensionProfile(extensions: nil, isNarrowerThanExtensions: false)
        }
        var intersection: Set<String>?
        var sawConstraint = false
        var narrower = false
        for profile in profiles {
            narrower = narrower || profile.isNarrowerThanExtensions
            guard let extensions = profile.extensions else { continue }
            sawConstraint = true
            intersection = intersection.map { $0.intersection(extensions) } ?? extensions
        }
        return ExtensionProfile(
            extensions: sawConstraint ? (intersection ?? []) : nil,
            isNarrowerThanExtensions: narrower
        )
    }

    private static func combineOr(_ profiles: [ExtensionProfile]) -> ExtensionProfile {
        if profiles.isEmpty {
            return ExtensionProfile(extensions: [], isNarrowerThanExtensions: false)
        }
        let narrower = profiles.contains(where: \.isNarrowerThanExtensions)
        if profiles.contains(where: { $0.extensions == nil }) {
            return ExtensionProfile(extensions: nil, isNarrowerThanExtensions: narrower)
        }
        let union = profiles.reduce(into: Set<String>()) { partial, profile in
            partial.formUnion(profile.extensions ?? [])
        }
        return ExtensionProfile(extensions: union, isNarrowerThanExtensions: narrower)
    }

    private static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
        return stripped.lowercased()
    }
}
