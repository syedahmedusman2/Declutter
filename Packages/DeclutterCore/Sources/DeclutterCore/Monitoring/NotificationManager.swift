import Foundation

public enum NotificationKind: String, Codable, CaseIterable, Sendable, Equatable {
    case batchCompleted
    case error
    case permissionProblem
    case needsDecision
    case monitoringPaused
}

public struct NotificationPreferences: Codable, Sendable, Equatable {
    public var enabled: [NotificationKind: Bool]

    public init(enabled: [NotificationKind: Bool] = [:]) {
        self.enabled = enabled
    }

    public func isEnabled(_ kind: NotificationKind) -> Bool {
        enabled[kind] ?? true
    }

    public static let allOn = NotificationPreferences()
}

public struct NotificationRequest: Sendable, Equatable {
    public var kind: NotificationKind
    public var title: String
    public var body: String

    public init(kind: NotificationKind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }
}

public protocol NotificationDelivering: Sendable {
    func deliver(_ request: NotificationRequest) async
}

/// Coalesces notification bursts into one delivery after a 5-second window.
public actor NotificationManager {
    private let clock: any OrganizerClock
    private let deliverer: any NotificationDelivering
    private let window: TimeInterval
    private var preferences = NotificationPreferences.allOn
    private var buckets: [NotificationKind: Bucket] = [:]
    private var flushTask: Task<Void, Never>?

    private struct Bucket {
        var count: Int
        var title: String
        var body: String
        var deadline: Date
    }

    public init(
        clock: any OrganizerClock,
        deliverer: any NotificationDelivering,
        window: TimeInterval = 5
    ) {
        self.clock = clock
        self.deliverer = deliverer
        self.window = window
    }

    public func update(preferences: NotificationPreferences) {
        self.preferences = preferences
    }

    public func notify(_ request: NotificationRequest, count: Int = 1) async {
        guard preferences.isEnabled(request.kind) else { return }
        let now = await clock.now()
        let total = max(count, 1)
        if var bucket = buckets[request.kind] {
            bucket.count += total
            bucket.body = Self.body(for: request.kind, count: bucket.count, fallback: request.body)
            buckets[request.kind] = bucket
        } else {
            buckets[request.kind] = Bucket(
                count: total,
                title: request.title,
                body: Self.body(for: request.kind, count: total, fallback: request.body),
                deadline: now.addingTimeInterval(window)
            )
        }
        if flushTask == nil {
            flushTask = Task { await self.flushLoop() }
        }
    }

    public func cancelPending() {
        flushTask?.cancel()
        flushTask = nil
        buckets.removeAll()
    }

    private func flushLoop() async {
        while !Task.isCancelled {
            guard let deadline = buckets.values.map(\.deadline).min() else {
                flushTask = nil
                return
            }
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return
            }
            if Task.isCancelled { return }
            let now = await clock.now()
            let due = buckets.filter { $0.value.deadline <= now }
            for (kind, bucket) in due {
                buckets[kind] = nil
                await deliverer.deliver(
                    NotificationRequest(kind: kind, title: bucket.title, body: bucket.body)
                )
            }
        }
    }

    private static func body(for kind: NotificationKind, count: Int, fallback: String) -> String {
        switch kind {
        case .batchCompleted:
            count == 1 ? "1 file organized" : "\(count) files organized"
        default:
            count <= 1 ? fallback : "\(fallback) (\(count))"
        }
    }
}
