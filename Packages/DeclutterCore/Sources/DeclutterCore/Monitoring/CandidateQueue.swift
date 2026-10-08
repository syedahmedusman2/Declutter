import Foundation

public struct QueuedCandidate: Sendable, Equatable {
    public var path: String
    public var eventID: UInt64
    public var readyAt: Date

    public init(path: String, eventID: UInt64, readyAt: Date) {
        self.path = path
        self.eventID = eventID
        self.readyAt = readyAt
    }
}

public actor CandidateQueue {
    public let debounce: TimeInterval
    public let capacity: Int
    private var items: [String: QueuedCandidate] = [:]
    private var order: [String] = []
    private var paused = false
    private var generation = 0
    private var pulsePending = false
    private var pulseWaiter: CheckedContinuation<Void, Never>?

    public init(debounce: TimeInterval = 0.5, capacity: Int = 10_000) {
        self.debounce = debounce
        self.capacity = max(capacity, 1)
    }

    public var waitingCount: Int { items.count }
    public var isPaused: Bool { paused }

    public func enqueue(path: String, eventID: UInt64, now: Date) {
        let readyAt = now.addingTimeInterval(debounce)
        if items[path] != nil {
            items[path] = QueuedCandidate(path: path, eventID: eventID, readyAt: readyAt)
        } else {
            if items.count >= capacity, let oldest = order.first {
                order.removeFirst()
                items[oldest] = nil
            }
            order.append(path)
            items[path] = QueuedCandidate(path: path, eventID: eventID, readyAt: readyAt)
        }
        signal()
    }

    public func setPaused(_ paused: Bool) {
        self.paused = paused
        signal()
    }

    /// Removes candidates whose debounce has elapsed. Returns nothing while paused.
    public func drainReady(now: Date) -> [QueuedCandidate] {
        guard !paused else { return [] }
        let readyPaths = order.filter { path in
            guard let item = items[path] else { return false }
            return item.readyAt <= now
        }
        var ready: [QueuedCandidate] = []
        ready.reserveCapacity(readyPaths.count)
        for path in readyPaths {
            guard let item = items.removeValue(forKey: path) else { continue }
            ready.append(item)
        }
        order.removeAll { items[$0] == nil }
        return ready
    }

    public func nextDeadline() -> Date? {
        guard !paused else { return nil }
        return items.values.map(\.readyAt).min()
    }

    public func waitForChange() async {
        if pulsePending {
            pulsePending = false
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if pulsePending {
                    pulsePending = false
                    continuation.resume()
                } else {
                    pulseWaiter = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWait() }
        }
    }

    private func signal() {
        generation += 1
        if let pulseWaiter {
            self.pulseWaiter = nil
            pulseWaiter.resume()
        } else {
            pulsePending = true
        }
    }

    private func cancelWait() {
        pulseWaiter?.resume()
        pulseWaiter = nil
    }
}
