import DeclutterCore
import Foundation
import Observation

@MainActor
enum AppRuntime {
    static var shared: AppModel?
}

@MainActor
@Observable
final class AppModel {
    let environment: AppEnvironment
    let settings: AppSettings
    let monitor: MonitorController
    var onOrganizeExisting: (() async -> Void)?
    var onReauthorize: (() async -> Void)?
    var onCommand: ((OrganizerCommand) -> Void)?
    private var didBootstrap = false

    init(environment: AppEnvironment, settings: AppSettings = AppSettings()) {
        self.environment = environment
        self.settings = settings
        monitor = MonitorController(environment: environment)
    }

    static func live() -> AppModel {
        AppModel(environment: .live())
    }

    var statusLine: String {
        MonitorStatusText.line(
            state: monitor.status.state,
            runInBackground: settings.runInBackground,
            waiting: monitor.status.waitingCount
        )
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        settings.synchronizeLaunchAtLogin()
        settings.applyDockIcon()
        monitor.startListening()
        monitor.observeWake()
        let preferences = settings.notificationPreferences
        let notifications = environment.notifications
        Task {
            await notifications.update(preferences: preferences)
            if settings.resumeMonitoringOnLaunch {
                await monitor.restoreIfNeeded(
                    conflict: settings.globalConflictPolicy,
                    moveSymlinks: settings.moveSymlinks
                )
            }
        }
    }

    func startMonitoring() {
        let mode = settings.automationMode
        let conflict = settings.globalConflictPolicy
        let symlinks = settings.moveSymlinks
        Task { await monitor.start(recovering: false, mode: mode, conflict: conflict, moveSymlinks: symlinks) }
    }

    func pauseMonitoring() {
        Task { await monitor.pause() }
    }

    func resumeMonitoring() {
        Task { await monitor.resume() }
    }

    func stopMonitoring() {
        Task { await monitor.stop() }
    }

    func organizeExisting() {
        Task { await onOrganizeExisting?() }
    }

    func reauthorize() {
        Task { await onReauthorize?() }
    }

    func send(_ command: OrganizerCommand) {
        onCommand?(command)
    }

    func togglePause() {
        switch monitor.status.state {
        case .monitoring:
            pauseMonitoring()
        case .paused:
            resumeMonitoring()
        default:
            startMonitoring()
        }
    }

    var uptimeDescription: String {
        guard let started = monitor.monitoringSince else { return "Not monitoring" }
        let seconds = max(0, Int(Date().timeIntervalSince(started)))
        let minutes = seconds / 60
        if minutes < 1 { return "Monitoring for less than a minute" }
        if minutes == 1 { return "Monitoring for 1 minute" }
        return "Monitoring for \(minutes) minutes"
    }

    func setNotification(_ kind: NotificationKind, enabled: Bool) {
        settings.setNotification(kind, enabled: enabled)
        let preferences = settings.notificationPreferences
        let notifications = environment.notifications
        Task { await notifications.update(preferences: preferences) }
    }
}

enum OrganizerCommand {
    case newCategory
    case rescan
    case execute
    case undoLastBatch
    case focusSearch
    case togglePause
}
