import AppKit
import DeclutterCore
import Foundation
import Observation

@MainActor
@Observable
final class MonitorController {
    private let environment: AppEnvironment
    private var scopeURLs: [URL] = []
    private var listenTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    private(set) var status = MonitorSnapshot(state: .stopped, waitingCount: 0, mode: nil, lastError: nil)
    private(set) var monitoringSince: Date?
    var detail: String?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func startListening() {
        guard listenTask == nil else { return }
        let coordinator = environment.coordinator
        listenTask = Task {
            let stream = await coordinator.statuses()
            for await next in stream {
                self.status = next
                if next.state == .monitoring {
                    if self.monitoringSince == nil {
                        self.monitoringSince = Date()
                    }
                } else if next.state == .stopped || next.state == .error || next.state == .permissionRequired {
                    self.monitoringSince = nil
                }
            }
        }
    }

    func observeWake() {
        guard wakeObserver == nil else { return }
        let coordinator = environment.coordinator
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await coordinator.reconcile() }
        }
    }

    func restoreIfNeeded(conflict: ConflictPolicy, moveSymlinks: Bool) async {
        let session = try? environment.sessionStore.load()
        guard session?.resumeState == .monitoring || session?.resumeState == .paused else { return }
        await start(recovering: true, mode: session?.mode, conflict: conflict, moveSymlinks: moveSymlinks)
        if session?.resumeState == .paused {
            await environment.coordinator.pause()
        }
    }

    func start(
        recovering: Bool,
        mode requestedMode: AutomationMode?,
        conflict: ConflictPolicy = .autoRename,
        moveSymlinks: Bool = false
    ) async {
        detail = nil
        guard var folder = try? environment.sourceFolders.load(), folder.bookmarkData != nil else {
            detail = "Choose a folder on the Files screen."
            status = MonitorSnapshot(state: .permissionRequired, waitingCount: 0, mode: nil, lastError: detail)
            return
        }
        let mode = requestedMode ?? folder.mode
        guard mode == .newOnly || mode == .existingAndNew else {
            detail = "Organize Existing moves files you confirm. Choose New Files Only or Existing and New to watch for downloads."
            return
        }
        folder.mode = mode
        try? environment.sourceFolders.save(folder)
        releaseAccess()
        do {
            guard let bookmark = folder.bookmarkData else { return }
            let access = try environment.permissions.resolve(bookmark, scope: environment.securityScope)
            scopeURLs.append(access.url)
            let categories = loadedCategories()
            let roots = destinationRoots(source: access.url, categories: categories)
            let configuration = MonitorConfiguration(
                sourceRoot: access.url,
                sourceID: folder.id,
                mode: mode,
                categories: categories,
                options: OrganizeOptions(
                    globalConflictPolicy: conflict,
                    permittedRoots: roots,
                    moveSymlinks: moveSymlinks
                )
            )
            await environment.coordinator.start(configuration, recovering: recovering)
        } catch {
            releaseAccess()
            detail = error.localizedDescription
            status = MonitorSnapshot(state: .permissionRequired, waitingCount: 0, mode: mode, lastError: detail)
            await environment.notifications.notify(
                NotificationRequest(
                    kind: .permissionProblem,
                    title: "Folder access is needed",
                    body: "Reauthorize the folder to keep organizing."
                )
            )
        }
    }

    func pause() async {
        await environment.coordinator.pause()
    }

    func resume() async {
        await environment.coordinator.resume()
    }

    func stop() async {
        await environment.coordinator.stop()
        releaseAccess()
    }

    func stopForQuit() async {
        await environment.coordinator.stopForQuit()
        releaseAccess()
    }

    private func loadedCategories() -> [OrganizerCategory] {
        if let stored = try? environment.categories.load(), !stored.categories.isEmpty {
            return stored.categories
        }
        return DefaultCategories.make()
    }

    private func destinationRoots(source: URL, categories: [OrganizerCategory]) -> [URL] {
        var roots = [source]
        for category in categories {
            guard case .absolute(let path, let bookmark) = category.destination else { continue }
            guard let bookmark else {
                roots.append(URL(fileURLWithPath: path))
                continue
            }
            if let access = try? environment.permissions.resolve(bookmark, scope: environment.securityScope) {
                scopeURLs.append(access.url)
                roots.append(access.url)
            } else {
                roots.append(URL(fileURLWithPath: path))
            }
        }
        return roots
    }

    private func releaseAccess() {
        for url in scopeURLs {
            environment.securityScope.stopAccessing(url)
        }
        scopeURLs.removeAll()
    }
}
