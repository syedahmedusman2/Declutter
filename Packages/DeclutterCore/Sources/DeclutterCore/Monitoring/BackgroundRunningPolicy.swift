import Foundation

public enum BackgroundPolicyError: Error, Equatable, LocalizedError, Sendable {
    case launchAtLoginRequiresBackground

    public var errorDescription: String? {
        switch self {
        case .launchAtLoginRequiresBackground:
            "Turn on background running before launching at login."
        }
    }
}

/// Rules for the optional background-running setting. The app applies the result to AppKit and `SMAppService`.
public struct BackgroundRunningPolicy: Sendable, Equatable {
    public var runInBackground: Bool
    public var showMenuBarIcon: Bool
    public var launchAtLogin: Bool
    public var showInDock: Bool
    public var resumeMonitoringOnLaunch: Bool
    public var alwaysQuit: Bool

    public init(
        runInBackground: Bool = true,
        showMenuBarIcon: Bool = true,
        launchAtLogin: Bool = false,
        showInDock: Bool = true,
        resumeMonitoringOnLaunch: Bool = true,
        alwaysQuit: Bool = false
    ) {
        self.runInBackground = runInBackground
        self.showMenuBarIcon = showMenuBarIcon
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.resumeMonitoringOnLaunch = resumeMonitoringOnLaunch
        self.alwaysQuit = alwaysQuit
    }

    public var menuBarVisible: Bool {
        runInBackground || showMenuBarIcon
    }

    public var terminatesWhenLastWindowCloses: Bool {
        !runInBackground
    }

    public func shouldPromptBeforeQuit(monitoringActive: Bool) -> Bool {
        !runInBackground && !alwaysQuit && monitoringActive
    }

    public func settingBackground(to enabled: Bool) -> (policy: BackgroundRunningPolicy, loginTurnedOff: Bool) {
        var next = self
        next.runInBackground = enabled
        let loginTurnedOff = !enabled && launchAtLogin
        if loginTurnedOff {
            next.launchAtLogin = false
        }
        return (next, loginTurnedOff)
    }

    public func settingLaunchAtLogin(to enabled: Bool) -> Result<BackgroundRunningPolicy, BackgroundPolicyError> {
        if enabled && !runInBackground {
            return .failure(.launchAtLoginRequiresBackground)
        }
        var next = self
        next.launchAtLogin = enabled
        return .success(next)
    }

    public func settingMenuBarIcon(to visible: Bool) -> BackgroundRunningPolicy {
        var next = self
        if runInBackground {
            next.showMenuBarIcon = true
        } else {
            next.showMenuBarIcon = visible
        }
        return next
    }
}

public enum MonitorStatusText {
    public static func line(state: MonitorState, runInBackground: Bool, waiting: Int) -> String {
        switch state {
        case .monitoring:
            return runInBackground
                ? "Monitoring (runs in background)"
                : "Monitoring (only while app is open)"
        case .paused:
            if waiting > 0 {
                return "Monitoring paused, \(waiting) \(waiting == 1 ? "file" : "files") waiting"
            }
            return "Paused"
        case .stopped:
            return "Stopped"
        case .permissionRequired:
            return "Folder access is needed"
        case .error:
            return "Monitoring stopped because of an error"
        }
    }
}
