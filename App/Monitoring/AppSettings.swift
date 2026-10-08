import AppKit
import DownloadOrganizerCore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let login: LaunchAtLoginManager

    private(set) var runInBackground: Bool
    private(set) var showMenuBarIcon: Bool
    private(set) var launchAtLogin: Bool
    private(set) var showInDock: Bool
    private(set) var resumeMonitoringOnLaunch: Bool
    private(set) var alwaysQuit: Bool
    private(set) var automationMode: AutomationMode
    private(set) var notificationPreferences: NotificationPreferences
    private(set) var didCompleteOnboarding: Bool
    private(set) var appearance: AppearanceChoice
    private(set) var globalConflictPolicy: ConflictPolicy
    private(set) var historyRetentionDays: Int
    private(set) var removeEmptyFolders: Bool
    private(set) var moveSymlinks: Bool
    private(set) var bulkConfirmationThreshold: Int
    var notice: String?

    init(defaults: UserDefaults = .standard, login: LaunchAtLoginManager = LaunchAtLoginManager()) {
        self.defaults = defaults
        self.login = login
        let storedBackground = defaults.object(forKey: Key.background) as? Bool
        let background = storedBackground ?? true
        runInBackground = background
        showMenuBarIcon = defaults.object(forKey: Key.menuBar) as? Bool ?? true
        launchAtLogin = false
        showInDock = defaults.object(forKey: Key.dock) as? Bool ?? true
        resumeMonitoringOnLaunch = defaults.object(forKey: Key.resume) as? Bool ?? background
        alwaysQuit = defaults.bool(forKey: Key.alwaysQuit)
        automationMode = AutomationMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .existingAndNew
        var enabled: [NotificationKind: Bool] = [:]
        for kind in NotificationKind.allCases {
            if defaults.object(forKey: Key.notify(kind)) != nil {
                enabled[kind] = defaults.bool(forKey: Key.notify(kind))
            }
        }
        notificationPreferences = NotificationPreferences(enabled: enabled)
        didCompleteOnboarding = defaults.bool(forKey: Key.onboarding)
        appearance = AppearanceChoice(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        globalConflictPolicy = ConflictPolicy(rawValue: defaults.string(forKey: Key.conflict) ?? "") ?? .autoRename
        let storedRetention = defaults.object(forKey: Key.retention) as? Int
        historyRetentionDays = storedRetention ?? 90
        removeEmptyFolders = defaults.object(forKey: Key.emptyFolders) as? Bool ?? true
        moveSymlinks = defaults.bool(forKey: Key.symlinks)
        bulkConfirmationThreshold = defaults.object(forKey: Key.bulk) as? Int ?? 50
    }

    var colorScheme: ColorScheme? { appearance.colorScheme }

    func configSnapshot() -> ConfigSettingsSnapshot {
        ConfigSettingsSnapshot(
            runInBackground: runInBackground,
            showMenuBarIcon: showMenuBarIcon,
            showInDock: showInDock,
            resumeMonitoringOnLaunch: resumeMonitoringOnLaunch,
            automationMode: automationMode.rawValue,
            historyRetentionDays: historyRetentionDays,
            removeEmptyFolders: removeEmptyFolders
        )
    }

    func applyImported(_ snapshot: ConfigSettingsSnapshot) {
        setRunInBackground(snapshot.runInBackground)
        setShowMenuBarIcon(snapshot.showMenuBarIcon)
        setShowInDock(snapshot.showInDock)
        setResumeMonitoringOnLaunch(snapshot.resumeMonitoringOnLaunch)
        if let mode = AutomationMode(rawValue: snapshot.automationMode) {
            setAutomationMode(mode)
        }
        setHistoryRetentionDays(snapshot.historyRetentionDays)
        setRemoveEmptyFolders(snapshot.removeEmptyFolders)
    }

    func settingsSummary() -> String {
        """
        runInBackground=\(runInBackground)
        showMenuBarIcon=\(showMenuBarIcon)
        showInDock=\(showInDock)
        resumeMonitoringOnLaunch=\(resumeMonitoringOnLaunch)
        automationMode=\(automationMode.rawValue)
        appearance=\(appearance.rawValue)
        conflict=\(globalConflictPolicy.rawValue)
        historyRetentionDays=\(historyRetentionDays)
        removeEmptyFolders=\(removeEmptyFolders)
        moveSymlinks=\(moveSymlinks)
        bulkConfirmationThreshold=\(bulkConfirmationThreshold)
        """
    }

    var policy: BackgroundRunningPolicy {
        BackgroundRunningPolicy(
            runInBackground: runInBackground,
            showMenuBarIcon: showMenuBarIcon,
            launchAtLogin: launchAtLogin,
            showInDock: showInDock,
            resumeMonitoringOnLaunch: resumeMonitoringOnLaunch,
            alwaysQuit: alwaysQuit
        )
    }

    var menuBarVisible: Bool { policy.menuBarVisible }

    func setRunInBackground(_ enabled: Bool) {
        let result = policy.settingBackground(to: enabled)
        runInBackground = result.policy.runInBackground
        if result.loginTurnedOff {
            launchAtLogin = false
            try? login.setEnabled(false)
            notice = "Launch at Login was turned off because the app no longer stays open in the background."
        }
        persist()
    }

    func setShowMenuBarIcon(_ visible: Bool) {
        let next = policy.settingMenuBarIcon(to: visible)
        showMenuBarIcon = next.showMenuBarIcon
        if runInBackground && !visible {
            notice = "The menu bar icon stays visible while the app runs in the background."
        }
        persist()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        switch policy.settingLaunchAtLogin(to: enabled) {
        case .failure(let error):
            notice = error.localizedDescription
        case .success(let next):
            do {
                try login.setEnabled(next.launchAtLogin)
                launchAtLogin = next.launchAtLogin
                notice = nil
                persist()
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    func setShowInDock(_ visible: Bool) {
        showInDock = visible
        persist()
        applyDockIcon()
    }

    func setResumeMonitoringOnLaunch(_ enabled: Bool) {
        resumeMonitoringOnLaunch = enabled
        persist()
    }

    func setAlwaysQuit(_ enabled: Bool) {
        alwaysQuit = enabled
        persist()
    }

    func setAutomationMode(_ mode: AutomationMode) {
        automationMode = mode
        persist()
    }

    func setDidCompleteOnboarding(_ completed: Bool) {
        didCompleteOnboarding = completed
        defaults.set(completed, forKey: Key.onboarding)
    }

    func setAppearance(_ choice: AppearanceChoice) {
        appearance = choice
        defaults.set(choice.rawValue, forKey: Key.appearance)
    }

    func setGlobalConflictPolicy(_ policy: ConflictPolicy) {
        globalConflictPolicy = policy
        defaults.set(policy.rawValue, forKey: Key.conflict)
    }

    func setHistoryRetentionDays(_ days: Int) {
        historyRetentionDays = days
        defaults.set(days, forKey: Key.retention)
    }

    func setRemoveEmptyFolders(_ enabled: Bool) {
        removeEmptyFolders = enabled
        defaults.set(enabled, forKey: Key.emptyFolders)
    }

    func setMoveSymlinks(_ enabled: Bool) {
        moveSymlinks = enabled
        defaults.set(enabled, forKey: Key.symlinks)
    }

    func setBulkConfirmationThreshold(_ count: Int) {
        bulkConfirmationThreshold = max(1, count)
        defaults.set(bulkConfirmationThreshold, forKey: Key.bulk)
    }

    func setNotification(_ kind: NotificationKind, enabled: Bool) {
        var next = notificationPreferences.enabled
        next[kind] = enabled
        notificationPreferences = NotificationPreferences(enabled: next)
        defaults.set(enabled, forKey: Key.notify(kind))
    }

    func synchronizeLaunchAtLogin() {
        let enabled = login.isEnabled()
        if enabled && !runInBackground {
            try? login.setEnabled(false)
            launchAtLogin = false
            notice = "Launch at Login was turned off because the app no longer stays open in the background."
        } else {
            launchAtLogin = enabled
        }
    }

    func applyDockIcon() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    private func persist() {
        defaults.set(runInBackground, forKey: Key.background)
        defaults.set(showMenuBarIcon, forKey: Key.menuBar)
        defaults.set(showInDock, forKey: Key.dock)
        defaults.set(resumeMonitoringOnLaunch, forKey: Key.resume)
        defaults.set(alwaysQuit, forKey: Key.alwaysQuit)
        defaults.set(automationMode.rawValue, forKey: Key.mode)
    }

    private enum Key {
        static let background = "settings.runInBackground"
        static let menuBar = "settings.showMenuBarIcon"
        static let dock = "settings.showInDock"
        static let resume = "settings.resumeMonitoringOnLaunch"
        static let alwaysQuit = "settings.alwaysQuit"
        static let mode = "settings.automationMode"
        static let onboarding = "settings.didCompleteOnboarding"
        static let appearance = "settings.appearance"
        static let conflict = "settings.globalConflictPolicy"
        static let retention = "settings.historyRetentionDays"
        static let emptyFolders = "settings.removeEmptyFolders"
        static let symlinks = "settings.moveSymlinks"
        static let bulk = "settings.bulkConfirmationThreshold"
        static func notify(_ kind: NotificationKind) -> String { "settings.notify.\(kind.rawValue)" }
    }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
