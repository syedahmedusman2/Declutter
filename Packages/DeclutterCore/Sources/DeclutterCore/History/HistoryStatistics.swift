import Foundation

public struct OrganizerStatistics: Sendable, Equatable {
    public var totalOrganized: Int
    public var organizedToday: Int
    public var skipped: Int
    public var failed: Int
    public var perCategory: [String: Int]
    public var lastOperation: Date?

    public init(
        totalOrganized: Int,
        organizedToday: Int,
        skipped: Int,
        failed: Int,
        perCategory: [String: Int],
        lastOperation: Date?
    ) {
        self.totalOrganized = totalOrganized
        self.organizedToday = organizedToday
        self.skipped = skipped
        self.failed = failed
        self.perCategory = perCategory
        self.lastOperation = lastOperation
    }

    public static let empty = OrganizerStatistics(
        totalOrganized: 0,
        organizedToday: 0,
        skipped: 0,
        failed: 0,
        perCategory: [:],
        lastOperation: nil
    )
}

public enum HistoryStatistics {
    public static func summarize(
        _ items: [HistoryItem],
        now: Date,
        calendar: Calendar = .current
    ) -> OrganizerStatistics {
        let today = calendar.startOfDay(for: now)
        var perCategory: [String: Int] = [:]
        var organized = 0
        var organizedToday = 0
        var skipped = 0
        var failed = 0
        for item in items {
            switch item.status {
            case .success:
                organized += 1
                perCategory[item.categoryName, default: 0] += 1
                if calendar.startOfDay(for: item.createdAt) == today {
                    organizedToday += 1
                }
            case .skipped:
                skipped += 1
            case .failed:
                failed += 1
            case .pending, .undone, .needsDecision:
                break
            }
        }
        return OrganizerStatistics(
            totalOrganized: organized,
            organizedToday: organizedToday,
            skipped: skipped,
            failed: failed,
            perCategory: perCategory,
            lastOperation: items.map(\.createdAt).max()
        )
    }
}
