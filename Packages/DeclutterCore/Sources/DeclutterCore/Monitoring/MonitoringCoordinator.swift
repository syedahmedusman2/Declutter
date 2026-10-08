import Foundation

public struct MonitorConfiguration: Sendable, Equatable {
    public var sourceRoot: URL
    public var sourceID: UUID
    public var mode: AutomationMode
    public var categories: [Category]
    public var options: OrganizeOptions
    public var debounce: TimeInterval
    public var stabilityDelay: TimeInterval
    public var reconcileInterval: TimeInterval

    public init(
        sourceRoot: URL,
        sourceID: UUID,
        mode: AutomationMode,
        categories: [Category],
        options: OrganizeOptions = OrganizeOptions(),
        debounce: TimeInterval = 0.5,
        stabilityDelay: TimeInterval = 2,
        reconcileInterval: TimeInterval = 15 * 60
    ) {
        self.sourceRoot = sourceRoot
        self.sourceID = sourceID
        self.mode = mode
        self.categories = categories
        self.options = options
        self.debounce = debounce
        self.stabilityDelay = stabilityDelay
        self.reconcileInterval = reconcileInterval
    }
}

public struct MonitorSnapshot: Sendable, Equatable {
    public var state: MonitorState
    public var waitingCount: Int
    public var mode: AutomationMode?
    public var lastError: String?

    public init(state: MonitorState, waitingCount: Int, mode: AutomationMode?, lastError: String?) {
        self.state = state
        self.waitingCount = waitingCount
        self.mode = mode
        self.lastError = lastError
    }
}

public protocol CategoryProviding: Sendable {
    func categories() async -> [Category]
}

public struct StaticCategories: CategoryProviding {
    private let values: [Category]

    public init(_ values: [Category]) {
        self.values = values
    }

    public func categories() async -> [Category] {
        values
    }
}

/// Watches one folder, waits until new files stop changing, then moves them.
public actor MonitoringCoordinator {
    private let events: any FileEventSource
    private let fileSystem: any FileSystemProviding
    private let organizer: FileOrganizer
    private let clock: any OrganizerClock
    private let notifications: NotificationManager
    private let scanner: FileScanner
    private let baselineStore: BaselineStore
    private let sessionStore: MonitorSessionStore
    private let probe: any StabilityProbing
    private let categories: any CategoryProviding

    private var queue: CandidateQueue
    private var stability: StabilityChecker
    private var configuration: MonitorConfiguration?
    private var baseline: [BaselineRecord] = []
    private var state: MonitorState = .stopped
    private var lastError: String?
    private var lastEventID: UInt64?
    private var loop: Task<Void, Never>?
    private var reader: Task<Void, Never>?
    private var reconcileLoop: Task<Void, Never>?
    private var statusContinuation: AsyncStream<MonitorSnapshot>.Continuation?

    public init(
        events: any FileEventSource,
        fileSystem: any FileSystemProviding,
        organizer: FileOrganizer,
        clock: any OrganizerClock,
        notifications: NotificationManager,
        scanner: FileScanner,
        baselineStore: BaselineStore,
        sessionStore: MonitorSessionStore,
        categories: any CategoryProviding,
        probe: (any StabilityProbing)? = nil
    ) {
        self.events = events
        self.fileSystem = fileSystem
        self.organizer = organizer
        self.clock = clock
        self.notifications = notifications
        self.scanner = scanner
        self.baselineStore = baselineStore
        self.sessionStore = sessionStore
        self.categories = categories
        self.probe = probe ?? FileSystemStabilityProbe(fileSystem: fileSystem)
        self.queue = CandidateQueue()
        self.stability = StabilityChecker(probe: self.probe, clock: clock)
    }

    public func statuses() -> AsyncStream<MonitorSnapshot> {
        AsyncStream { continuation in
            statusContinuation = continuation
            continuation.yield(snapshot())
        }
    }

    public func snapshot() -> MonitorSnapshot {
        MonitorSnapshot(
            state: state,
            waitingCount: 0,
            mode: configuration?.mode,
            lastError: lastError
        )
    }

    public func waitingCount() async -> Int {
        await queue.waitingCount
    }

    public func currentState() -> MonitorState {
        state
    }

    /// Starts watching. `recovering` reuses the saved baseline and FSEvents id.
    public func start(_ configuration: MonitorConfiguration, recovering: Bool) async {
        await stop(intent: nil)
        guard configuration.mode == .newOnly || configuration.mode == .existingAndNew else {
            state = .stopped
            self.configuration = configuration
            await publish()
            return
        }
        self.configuration = configuration
        queue = CandidateQueue(debounce: configuration.debounce)
        stability = StabilityChecker(probe: probe, clock: clock, delay: configuration.stabilityDelay)
        lastError = nil
        do {
            if recovering {
                baseline = try baselineStore.load()
                let session = try sessionStore.load()
                lastEventID = session?.lastEventID
            } else {
                baseline = try captureBaseline(root: configuration.sourceRoot)
                try baselineStore.save(baseline)
                lastEventID = nil
            }
        } catch {
            state = .error
            lastError = error.localizedDescription
            await publish()
            return
        }
        state = .monitoring
        await publish()
        let since = recovering ? lastEventID : nil
        let stream = events.events(for: configuration.sourceRoot, since: since)
        reader = Task {
            for await event in stream {
                if Task.isCancelled { break }
                await self.ingest(event)
            }
        }
        loop = Task {
            await self.processLoop()
        }
        if configuration.reconcileInterval > 0 {
            reconcileLoop = Task {
                await self.reconcileTimer()
            }
        }
        try? await saveSession(intent: .monitoring)
        if recovering {
            await reconcile()
        }
    }

    public func pause() async {
        guard state == .monitoring else { return }
        state = .paused
        await queue.setPaused(true)
        await publish()
        try? await saveSession(intent: .paused)
        await notifications.notify(
            NotificationRequest(
                kind: .monitoringPaused,
                title: "Monitoring paused",
                body: "New files will wait until monitoring resumes."
            )
        )
    }

    public func resume() async {
        guard state == .paused else { return }
        state = .monitoring
        await queue.setPaused(false)
        await publish()
        try? await saveSession(intent: .monitoring)
    }

    /// User stop. The next launch stays stopped.
    public func stop() async {
        await stop(intent: .stopped)
    }

    /// App quit. The saved state is whatever was running so launch can resume it.
    public func stopForQuit() async {
        let intent: MonitorState = (state == .paused) ? .paused : (state == .monitoring ? .monitoring : .stopped)
        await stop(intent: intent)
    }

    public func reconcile() async {
        guard let configuration, state == .monitoring || state == .paused else { return }
        let files = (try? scanner.scanAll(source: configuration.sourceRoot)) ?? []
        let now = await clock.now()
        for file in files where !BaselineStore.contains(file, in: baseline) {
            await queue.enqueue(path: file.url.path, eventID: lastEventID ?? 0, now: now)
        }
    }

    private func stop(intent: MonitorState?) async {
        reader?.cancel()
        loop?.cancel()
        reconcileLoop?.cancel()
        reader = nil
        loop = nil
        reconcileLoop = nil
        await clock.wake()
        await notifications.cancelPending()
        if let intent {
            try? await saveSession(intent: intent)
        }
        state = .stopped
        await publish()
    }

    private func ingest(_ event: FileEvent) async {
        guard let configuration else { return }
        lastEventID = max(lastEventID ?? 0, event.eventID)
        let url = URL(fileURLWithPath: event.path)
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let root = configuration.sourceRoot.standardizedFileURL.path
        guard parent == root else { return }
        if event.flags.contains(.isDirectory) || event.flags.contains(.removed) { return }
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return }
        let now = await clock.now()
        await queue.enqueue(path: url.path, eventID: event.eventID, now: now)
        try? await saveSession(intent: state == .paused ? .paused : .monitoring)
    }

    private func processLoop() async {
        while !Task.isCancelled {
            let now = await clock.now()
            let ready = await queue.drainReady(now: now)
            if ready.isEmpty {
                let deadline = await queue.nextDeadline()
                do {
                    try await waitForNext(deadline: deadline)
                } catch {
                    break
                }
                continue
            }
            for candidate in ready {
                if Task.isCancelled { return }
                await handle(candidate)
            }
            await publishWaiting()
        }
    }

    private func handle(_ candidate: QueuedCandidate) async {
        guard let configuration else { return }
        let url = URL(fileURLWithPath: candidate.path)
        let result = await stability.waitUntilStable(url)
        switch result {
        case .stable(let snapshot):
            if BaselineStore.contains(snapshot, in: baseline) { return }
            await organize(snapshot, configuration: configuration)
        case .changing, .busy:
            let now = await clock.now()
            await queue.enqueue(path: candidate.path, eventID: candidate.eventID, now: now)
        case .temporary, .disappeared:
            break
        }
    }

    private func organize(_ snapshot: FileSnapshot, configuration: MonitorConfiguration) async {
        let categories = await categories.categories()
        let usable = categories.isEmpty ? configuration.categories : categories
        let planner = OrganizePlanner(
            fileSystem: fileSystem,
            categories: usable,
            sourceRoot: configuration.sourceRoot,
            options: configuration.options
        )
        guard let move = planner.plan(files: [snapshot]).first else { return }
        if move.action == .needsDecision || move.action == .replace {
            await notifications.notify(
                NotificationRequest(
                    kind: .needsDecision,
                    title: "A file needs a decision",
                    body: "\(snapshot.name) is waiting in Preview."
                )
            )
            return
        }
        guard move.action == .move else { return }
        let execution = organizer.execute(
            plan: [move],
            sourceRoot: configuration.sourceRoot,
            options: configuration.options,
            replaceConfirmed: false
        )
        let batch = await execution.result.value
        if batch.succeeded > 0 {
            await notifications.notify(
                NotificationRequest(kind: .batchCompleted, title: "Files organized", body: "Files organized"),
                count: batch.succeeded
            )
        }
        if batch.failed > 0 {
            await notifications.notify(
                NotificationRequest(
                    kind: .error,
                    title: "A file could not be organized",
                    body: batch.results.first { $0.status == .failed }?.message ?? "The file could not be moved."
                )
            )
        }
    }

    private func waitForNext(deadline: Date?) async throws {
        let clock = self.clock
        let queue = self.queue
        try await withThrowingTaskGroup(of: Void.self) { group in
            if let deadline {
                group.addTask {
                    try? await clock.sleep(until: deadline)
                }
            }
            group.addTask {
                await queue.waitForChange()
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func reconcileTimer() async {
        guard let interval = configuration?.reconcileInterval, interval > 0 else { return }
        while !Task.isCancelled {
            let started = await clock.now()
            do {
                try await clock.sleep(until: started.addingTimeInterval(interval))
            } catch {
                return
            }
            if Task.isCancelled { return }
            await reconcile()
        }
    }

    private func captureBaseline(root: URL) throws -> [BaselineRecord] {
        try scanner.scanAll(source: root).map { snapshot in
            BaselineRecord(path: snapshot.url.path, fileID: snapshot.fileID)
        }
    }

    private func saveSession(intent: MonitorState) async throws {
        guard let configuration else { return }
        let session = MonitorSession(
            lastEventID: lastEventID,
            resumeState: intent,
            sourceID: configuration.sourceID,
            mode: configuration.mode
        )
        try sessionStore.save(session)
    }

    private func publish() async {
        let count = await queue.waitingCount
        statusContinuation?.yield(
            MonitorSnapshot(state: state, waitingCount: count, mode: configuration?.mode, lastError: lastError)
        )
    }

    private func publishWaiting() async {
        let count = await queue.waitingCount
        statusContinuation?.yield(
            MonitorSnapshot(state: state, waitingCount: count, mode: configuration?.mode, lastError: lastError)
        )
    }
}
