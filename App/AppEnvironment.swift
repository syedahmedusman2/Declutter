import DeclutterCore
import Foundation

struct AppEnvironment {
    var scanner: FileScanner
    var permissions: PermissionManager
    var securityScope: any SecurityScopeControlling
    var sourceFolders: SourceFolderFileStore
    var categories: CategoryStore
    var snapshotLoader: FileSnapshotLoader
    var fileSystem: SystemFileSystem
    var journal: FileJournal
    var history: HistoryStore
    var organizer: FileOrganizer
    var notifications: NotificationManager
    var sessionStore: MonitorSessionStore
    var coordinator: MonitoringCoordinator

    static func live() -> AppEnvironment {
        let fileSystem = SystemFileSystem()
        let clock = SystemOrganizerClock()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.applicationSupportDirectory
        let directory = support.appendingPathComponent(AppBranding.bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = FileJournal(fileURL: directory.appendingPathComponent("journal.json"))
        let categories = CategoryStore(fileURL: directory.appendingPathComponent("config.json"))
        let notifications = NotificationManager(clock: clock, deliverer: UserNotificationPoster())
        let history = HistoryStore.make(in: directory)
        let organizer = FileOrganizer(fileSystem: fileSystem, journal: journal, history: history)
        let scanner = FileScanner(fileSystem: fileSystem)
        return AppEnvironment(
            scanner: scanner,
            permissions: PermissionManager(store: SecurityScopedBookmarkStore()),
            securityScope: SystemSecurityScope(),
            sourceFolders: SourceFolderFileStore(fileURL: directory.appendingPathComponent("source-folder.json")),
            categories: categories,
            snapshotLoader: FileSnapshotLoader(fileSystem: fileSystem),
            fileSystem: fileSystem,
            journal: journal,
            history: history,
            organizer: organizer,
            notifications: notifications,
            sessionStore: MonitorSessionStore(fileURL: directory.appendingPathComponent("monitor-session.json")),
            coordinator: MonitoringCoordinator(
                events: FSEventsMonitor(),
                fileSystem: fileSystem,
                organizer: organizer,
                clock: clock,
                notifications: notifications,
                scanner: scanner,
                baselineStore: BaselineStore(fileURL: directory.appendingPathComponent("baseline.json")),
                sessionStore: MonitorSessionStore(fileURL: directory.appendingPathComponent("monitor-session.json")),
                categories: StoreCategories(store: categories)
            )
        )
    }
}

private struct StoreCategories: CategoryProviding {
    let store: CategoryStore

    func categories() async -> [DeclutterCore.Category] {
        if let stored = try? store.load(), !stored.categories.isEmpty {
            return stored.categories
        }
        return DefaultCategories.make()
    }
}
