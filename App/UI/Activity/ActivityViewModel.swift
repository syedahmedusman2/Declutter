import DeclutterCore
import Foundation
import Observation

struct ActivityDay: Identifiable {
    var id: Date { day }
    var day: Date
    var title: String
    var items: [HistoryItem]
}

@MainActor
@Observable
final class ActivityViewModel {
    private let environment: AppEnvironment
    private let settings: AppSettings

    private(set) var items: [HistoryItem] = []
    private(set) var stats = OrganizerStatistics.empty
    var search = ""
    var statusFilter: OperationStatus?
    var categoryFilter = ""
    var range: ActivityRange = .any
    var selection: UUID?
    var reportText: String?
    var errorText: String?

    init(environment: AppEnvironment, settings: AppSettings) {
        self.environment = environment
        self.settings = settings
    }

    var categories: [String] {
        Array(Set(items.map(\.categoryName))).sorted()
    }

    var days: [ActivityDay] {
        let calendar = Calendar.current
        let filtered = items.filter { matches($0) }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            ActivityDay(
                day: day,
                title: day.formatted(date: .complete, time: .omitted),
                items: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    var selected: HistoryItem? {
        items.first { $0.id == selection }
    }

    func reload() async {
        do {
            items = try await environment.history.query(HistoryQuery(limit: 1_000))
            stats = try await environment.history.statistics()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    func undoSelected() async {
        guard let selected else { return }
        await undo(ids: [selected.id])
    }

    func undoLastBatch() async {
        let report = await MoveUndoManager(
            fileSystem: environment.fileSystem,
            history: environment.history
        ).undoLastBatch(conflict: .renameBack, removeEmptyFolders: settings.removeEmptyFolders)
        reportText = Self.describe(report)
        await reload()
    }

    private func undo(ids: [UUID]) async {
        let report = await MoveUndoManager(
            fileSystem: environment.fileSystem,
            history: environment.history
        ).undo(ids: ids, conflict: .renameBack, removeEmptyFolders: settings.removeEmptyFolders)
        reportText = Self.describe(report)
        await reload()
    }

    private func matches(_ item: HistoryItem) -> Bool {
        if let statusFilter, item.status != statusFilter { return false }
        if !categoryFilter.isEmpty, item.categoryName != categoryFilter { return false }
        if let start = range.start {
            if item.createdAt < start { return false }
        }
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return true }
        let haystack = "\(item.originalName) \(item.finalName) \(item.categoryName) \(item.ruleSummary) \(item.message)".lowercased()
        return haystack.contains(needle)
    }

    private static func describe(_ report: UndoReport) -> String {
        if report.failed.isEmpty {
            return "Undone \(report.succeeded)."
        }
        let details = report.failed.map { "\($0.name): \($0.reason)" }.joined(separator: " ")
        return "Undone \(report.succeeded). Failed \(report.failed.count). \(details)"
    }
}

enum ActivityRange: String, CaseIterable, Identifiable {
    case any
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any time"
        case .today: "Today"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        }
    }

    var start: Date? {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .any:
            return nil
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .month:
            return calendar.date(byAdding: .day, value: -30, to: now)
        }
    }
}
