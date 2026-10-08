import Foundation

public protocol OrganizerClock: Sendable {
    func now() async -> Date
    func sleep(until deadline: Date) async throws
    func wake() async
}

public struct SystemOrganizerClock: OrganizerClock {
    public init() {}

    public func now() async -> Date {
        Date()
    }

    public func sleep(until deadline: Date) async throws {
        let interval = deadline.timeIntervalSinceNow
        if interval > 0 {
            try await Task.sleep(for: .seconds(interval))
        }
    }

    public func wake() async {}
}

/// Clock whose time moves only when a test calls `advance`.
public actor ManualClock: OrganizerClock {
    private var current: Date
    private var waiters: [UUID: (deadline: Date, continuation: CheckedContinuation<Void, Error>)] = [:]

    public init(startingAt date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = date
    }

    public func now() -> Date {
        current
    }

    public func hasWaiter() -> Bool {
        !waiters.isEmpty
    }

    public func soonestWait() -> TimeInterval? {
        guard let next = waiters.values.map(\.deadline).min() else { return nil }
        return max(0, next.timeIntervalSince(current))
    }

    public func hasWaiter(dueWithin interval: TimeInterval) -> Bool {
        let limit = current.addingTimeInterval(interval)
        return waiters.values.contains { $0.deadline <= limit }
    }

    @discardableResult
    public func advance(by interval: TimeInterval) -> Int {
        current = current.addingTimeInterval(interval)
        return resumeDueWaiters()
    }

    public func wake() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending.values {
            waiter.continuation.resume()
        }
    }

    public func sleep(until deadline: Date) async throws {
        if deadline <= current { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if deadline <= current {
                    continuation.resume()
                    return
                }
                waiters[id] = (deadline, continuation)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CancellationError())
    }

    @discardableResult
    private func resumeDueWaiters() -> Int {
        let due = waiters.filter { $0.value.deadline <= current }
        for id in due.keys {
            waiters.removeValue(forKey: id)?.continuation.resume()
        }
        return due.count
    }
}
