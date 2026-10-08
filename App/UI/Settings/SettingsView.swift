import DownloadOrganizerCore
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @State private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            AutomationTab(model: model)
                .tabItem { Label("Automation", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.automation)
            ConflictsTab(model: model)
                .tabItem { Label("Conflicts", systemImage: "doc.on.doc") }
                .tag(SettingsTab.conflicts)
            NotificationsTab(model: model)
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            SafetyTab(model: model)
                .tabItem { Label("Safety", systemImage: "checkmark.shield") }
                .tag(SettingsTab.safety)
            HistoryTab(model: model)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(SettingsTab.history)
        }
        .frame(width: 560, height: 460)
        .preferredColorScheme(model.settings.colorScheme)
    }
}

private enum SettingsTab: Hashable {
    case general
    case automation
    case conflicts
    case notifications
    case safety
    case history
}

private struct GeneralTab: View {
    var model: AppModel

    var body: some View {
        Form {
            Section("Folder") {
                Text("Choose or reauthorize the folder on the Files screen. The path is not stored in exported settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reauthorize Folder") { model.reauthorize() }
                    .accessibilityHint("Returns to Files and opens the folder chooser.")
            }
            Section("Appearance") {
                Picker("Appearance", selection: Binding(
                    get: { model.settings.appearance },
                    set: { model.settings.setAppearance($0) }
                )) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Text("Light, Dark, and System all use the same labels. Status is an icon plus words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Background") {
                Toggle("Keep running in background when the window is closed", isOn: background)
                Toggle("Show menu bar icon", isOn: menuBar)
                    .disabled(model.settings.runInBackground)
                if model.settings.runInBackground {
                    Text("The menu bar icon stays visible while the app runs in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Launch at Login", isOn: login)
                    .disabled(!model.settings.runInBackground)
                if !model.settings.runInBackground {
                    Text("Turn on background running before launching at login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show in Dock", isOn: dock)
            }
            notice
        }
        .formStyle(.grouped)
    }

    private var background: Binding<Bool> {
        Binding(get: { model.settings.runInBackground }, set: { model.settings.setRunInBackground($0) })
    }

    private var menuBar: Binding<Bool> {
        Binding(get: { model.settings.menuBarVisible }, set: { model.settings.setShowMenuBarIcon($0) })
    }

    private var login: Binding<Bool> {
        Binding(get: { model.settings.launchAtLogin }, set: { model.settings.setLaunchAtLogin($0) })
    }

    private var dock: Binding<Bool> {
        Binding(get: { model.settings.showInDock }, set: { model.settings.setShowInDock($0) })
    }

    @ViewBuilder
    private var notice: some View {
        if let notice = model.settings.notice {
            Text(notice)
        }
    }
}

private struct AutomationTab: View {
    var model: AppModel

    var body: some View {
        Form {
            Section("Watch") {
                Picker("Mode", selection: Binding(
                    get: { model.settings.automationMode },
                    set: { model.settings.setAutomationMode($0) }
                )) {
                    Text("New files only").tag(AutomationMode.newOnly)
                    Text("Existing and new").tag(AutomationMode.existingAndNew)
                    Text("Existing files only").tag(AutomationMode.existingOnly)
                }
                Text("Organize Existing works in every mode. Monitoring moves only new, stable files after about two seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Launch") {
                Toggle("Resume monitoring on launch", isOn: Binding(
                    get: { model.settings.resumeMonitoringOnLaunch },
                    set: { model.settings.setResumeMonitoringOnLaunch($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

private struct ConflictsTab: View {
    var model: AppModel

    var body: some View {
        Form {
            Section("When a file already has that name") {
                Picker("Default", selection: Binding(
                    get: { model.settings.globalConflictPolicy },
                    set: { model.settings.setGlobalConflictPolicy($0) }
                )) {
                    Text("Ask").tag(ConflictPolicy.ask)
                    Text("Auto Rename").tag(ConflictPolicy.autoRename)
                    Text("Skip").tag(ConflictPolicy.skip)
                    Text("Replace").tag(ConflictPolicy.replace)
                }
                Text("A category can override this. Replace moves the existing file to the Trash only after you confirm, and undo can restore it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Large batches") {
                Stepper(
                    "Confirm before moving \(model.settings.bulkConfirmationThreshold) or more files",
                    value: Binding(
                        get: { model.settings.bulkConfirmationThreshold },
                        set: { model.settings.setBulkConfirmationThreshold($0) }
                    ),
                    in: 1...10_000
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotificationsTab: View {
    var model: AppModel

    var body: some View {
        Form {
            Section("Notify me about") {
                ForEach(NotificationKind.allCases, id: \.rawValue) { kind in
                    Toggle(label(kind), isOn: Binding(
                        get: { model.settings.notificationPreferences.isEnabled(kind) },
                        set: { model.setNotification(kind, enabled: $0) }
                    ))
                }
            }
            Text("A burst of files becomes one notification.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func label(_ kind: NotificationKind) -> String {
        switch kind {
        case .batchCompleted: "Files organized"
        case .error: "Errors"
        case .permissionProblem: "Folder access"
        case .needsDecision: "Files that need a decision"
        case .monitoringPaused: "Monitoring paused"
        }
    }
}

private struct SafetyTab: View {
    var model: AppModel

    var body: some View {
        Form {
            Section("Moves") {
                Toggle("Remove empty category folders after undo", isOn: Binding(
                    get: { model.settings.removeEmptyFolders },
                    set: { model.settings.setRemoveEmptyFolders($0) }
                ))
                Toggle("Move symbolic links", isOn: Binding(
                    get: { model.settings.moveSymlinks },
                    set: { model.settings.setMoveSymlinks($0) }
                ))
                Text("The app never deletes files. Replace sends the previous file to the Trash. One failed file does not stop the rest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HistoryTab: View {
    var model: AppModel
    @State private var retention = 90
    @State private var includePaths = false
    @State private var preview: PendingImport?
    @State private var message: String?
    @State private var confirmClearHistory = false
    @State private var confirmClearUndo = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Keep history") {
                Picker("Retention", selection: $retention) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("365 days").tag(365)
                    Text("Forever").tag(0)
                }
                .onChange(of: retention) { _, days in
                    model.settings.setHistoryRetentionDays(days)
                    Task { try? await model.environment.history.applyRetention(days: days) }
                }
            }
            Section("Records") {
                Button("Clear History") { confirmClearHistory = true }
                    .accessibilityHint("Removes the activity log. This does not move files.")
                Button("Clear Undo Records") { confirmClearUndo = true }
                    .accessibilityHint("Keeps the log and turns off undo for those moves.")
            }
            Section("Configuration") {
                Button("Export Configuration") { exportConfig() }
                Button("Import Configuration") { importConfig() }
                Button("Reset to Defaults") { confirmReset = true }
                Button("Export Diagnostics") { exportDiagnostics() }
                Toggle("Include file paths in diagnostics", isOn: $includePaths)
                Text("Exports leave out bookmarks. Paths in diagnostics are redacted unless you include them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message)
            }
        }
        .formStyle(.grouped)
        .onAppear { retention = model.settings.historyRetentionDays }
        .confirmationDialog("Clear all history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                Task { try? await model.environment.history.clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear undo records?", isPresented: $confirmClearUndo, titleVisibility: .visible) {
            Button("Clear Undo Records", role: .destructive) {
                Task { try? await model.environment.history.clearUndoRecords() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The activity log stays. Those moves can no longer be undone.")
        }
        .confirmationDialog("Reset categories to the defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { resetDefaults() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $preview) { item in
            ImportPreviewSheet(preview: item.preview) {
                apply(item)
            }
        }
    }

    private func exportConfig() {
        guard let url = FolderPicker.save(title: "Export Configuration", name: "download-organizer-config.json", ext: "json") else { return }
        do {
            let stored = try model.environment.categories.load()
            let categories = stored?.categories ?? DefaultCategories.make()
            let data = try ConfigTransfer.export(categories: categories, settings: model.settings.configSnapshot())
            try write(data, to: url)
            message = "Configuration exported."
        } catch {
            message = error.localizedDescription
        }
    }

    private func importConfig() {
        guard let url = FolderPicker.openJSON() else { return }
        do {
            let data = try read(url)
            let current = try model.environment.categories.load()?.categories ?? []
            preview = PendingImport(preview: try ConfigTransfer.validate(data, current: current))
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply(_ item: PendingImport) {
        do {
            try model.environment.categories.save(item.preview.categories)
            model.settings.applyImported(item.preview.settings)
            message = "Configuration imported."
            preview = nil
            NotificationCenter.default.post(name: .organizerCategoriesDidChange, object: nil)
        } catch {
            message = error.localizedDescription
        }
    }

    private func resetDefaults() {
        do {
            try model.environment.categories.save(ConfigTransfer.defaults())
            message = "Categories reset to the defaults."
            NotificationCenter.default.post(name: .organizerCategoriesDidChange, object: nil)
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportDiagnostics() {
        guard let url = FolderPicker.save(title: "Export Diagnostics", name: "download-organizer-diagnostics.zip", ext: "zip") else { return }
        Task {
            do {
                let history = try await model.environment.history.query(HistoryQuery(limit: 50))
                let version = ProcessInfo.processInfo.operatingSystemVersionString
                let report = DiagnosticsReport(
                    appVersion: AppBranding.version,
                    systemVersion: version,
                    settingsSummary: model.settings.settingsSummary(),
                    logLines: ["Names in the log are privacy-marked. This file lists recent statuses."],
                    history: history
                )
                try write(DiagnosticsExporter.zip(report: report, includePaths: includePaths), to: url)
                message = "Diagnostics exported."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func read(_ url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func write(_ data: Data, to url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
    }
}

private struct ImportPreviewSheet: View {
    var preview: ImportPreview
    var apply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import summary")
                .font(.title3)
            Text("Added: \(list(preview.added))")
            Text("Removed: \(list(preview.removed))")
            Text("Changed: \(list(preview.changed))")
            ForEach(preview.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
            }
            Text("Bookmarks are not imported. Apply only if this summary looks right.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func list(_ names: [String]) -> String {
        names.isEmpty ? "None" : names.joined(separator: ", ")
    }
}

private struct PendingImport: Identifiable {
    let id = UUID()
    var preview: ImportPreview
}

extension Notification.Name {
    static let organizerCategoriesDidChange = Notification.Name("organizerCategoriesDidChange")
}
