import DeclutterCore
import SwiftUI

enum AppSection: String, Hashable {
    case dashboard
    case files
    case preview
    case rules
    case activity
}

struct RootView: View {
    var model: AppModel
    private let environment: AppEnvironment
    @State private var library: CategoryLibrary
    @State private var scanModel: ScanViewModel
    @State private var previewModel: PreviewViewModel
    @State private var rulesModel: RulesViewModel
    @State private var activityModel: ActivityViewModel
    @State private var section: AppSection? = .dashboard
    @State private var showOnboarding = false
    @State private var searchFocus = 0

    init(model: AppModel) {
        self.model = model
        environment = model.environment
        let library = CategoryLibrary(store: model.environment.categories)
        _library = State(initialValue: library)
        _scanModel = State(initialValue: ScanViewModel(environment: model.environment, library: library))
        _previewModel = State(initialValue: PreviewViewModel(environment: model.environment, library: library))
        _rulesModel = State(initialValue: RulesViewModel(environment: model.environment, library: library))
        _activityModel = State(initialValue: ActivityViewModel(environment: model.environment, settings: model.settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            MonitorBar(model: model)
            Divider()
            split
        }
        .respectReduceMotion()
        .preferredColorScheme(model.settings.colorScheme)
    }

    private var split: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Dashboard", systemImage: "gauge")
                    .tag(AppSection.dashboard)
                    .accessibilityLabel("Dashboard")
                Label("Files", systemImage: "folder")
                    .tag(AppSection.files)
                Label("Preview", systemImage: "checklist")
                    .tag(AppSection.preview)
                Label("Rules", systemImage: "list.bullet")
                    .tag(AppSection.rules)
                Label("Activity", systemImage: "clock")
                    .tag(AppSection.activity)
            }
            .navigationTitle(AppBranding.name)
            .listStyle(.sidebar)
        } detail: {
            switch section ?? .dashboard {
            case .dashboard:
                DashboardView(
                    model: model,
                    activity: activityModel,
                    folderPath: scanModel.folderPath,
                    needsReauthorization: scanModel.needsReauthorization,
                    permissionMessage: scanModel.errorText,
                    openRules: { section = .rules },
                    reauthorize: { reauthorize() }
                )
            case .files:
                ScanView(model: scanModel) {
                    section = .preview
                    Task { await refreshPreview() }
                }
            case .preview:
                PreviewView(model: previewModel, searchFocus: searchFocus) {
                    model.reauthorize()
                }
            case .rules:
                RulesView(model: rulesModel)
            case .activity:
                ActivityView(model: activityModel, searchFocus: searchFocus)
            }
        }
        .frame(minWidth: 920, minHeight: 560)
        .task {
            model.onOrganizeExisting = {
                section = .preview
                await refreshPreview()
            }
            model.onReauthorize = { reauthorize() }
            model.onCommand = { command in
                handle(command)
            }
            previewModel.onOrganized = {
                await scanModel.rescan()
                await activityModel.reload()
            }
            await library.load()
            model.bootstrap()
            await reconcileJournal()
            await scanModel.restoreSavedFolder()
            let hasFolder = (try? environment.sourceFolders.load()) != nil
            if hasFolder {
                model.settings.setDidCompleteOnboarding(true)
            } else if !model.settings.didCompleteOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: library.categories) { _, _ in
            scanModel.reclassify()
            previewModel.markStale()
        }
        .onChange(of: section) { _, newValue in
            guard newValue == .preview else { return }
            Task { await previewModel.refreshIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizerCategoriesDidChange)) { _ in
            Task { await library.load() }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                model: model,
                scan: scanModel,
                preview: previewModel,
                library: library
            ) { organize in
                showOnboarding = false
                model.settings.setDidCompleteOnboarding(true)
                guard organize else { return }
                section = .preview
                Task { await previewModel.performExecute() }
            }
            .onAppear { applyOrganizeOptions() }
        }
        .task(id: section) {
            guard section == .activity else { return }
            while !Task.isCancelled {
                await activityModel.reload()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func handle(_ command: OrganizerCommand) {
        switch command {
        case .newCategory:
            section = .rules
            rulesModel.addCategory()
        case .rescan:
            section = .files
            Task { await scanModel.rescan() }
        case .execute:
            section = .preview
            applyOrganizeOptions()
            previewModel.requestExecute()
        case .undoLastBatch:
            section = .activity
            Task { await activityModel.undoLastBatch() }
        case .focusSearch:
            if section != .preview && section != .activity {
                section = .activity
            }
            searchFocus += 1
        case .togglePause:
            model.togglePause()
        }
    }

    private func reauthorize() {
        section = .files
        Task { await scanModel.chooseFolderAndScan() }
    }

    private func refreshPreview() async {
        applyOrganizeOptions()
        await previewModel.refresh()
    }

    private func applyOrganizeOptions() {
        previewModel.globalConflictPolicy = model.settings.globalConflictPolicy
        previewModel.moveSymlinks = model.settings.moveSymlinks
        previewModel.bulkConfirmationThreshold = model.settings.bulkConfirmationThreshold
    }

    private func reconcileJournal() async {
        do {
            _ = try await environment.journal.reconcilePending(using: environment.fileSystem)
            let entries = try await environment.journal.load()
            try await environment.history.importJournal(entries)
            try await environment.history.applyRetention(days: model.settings.historyRetentionDays)
        } catch {
            CoreLog.organizer.error(
                "Could not reconcile the move journal: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
