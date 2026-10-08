import DownloadOrganizerCore
import Foundation
import Observation

struct ScannedFile: Identifiable, Sendable {
    var id: String { url.path }
    var url: URL
    var name: String
    var categoryName: String
    var destinationPath: String
}

@MainActor
@Observable
final class ScanViewModel {
    private let environment: AppEnvironment
    private let library: CategoryLibrary
    private var didRestore = false
    private var savedFolder: SourceFolder?
    private var snapshots: [FileSnapshot] = []
    private var sourceURL: URL?

    private(set) var rows: [ScannedFile] = []
    private(set) var folderPath: String?
    private(set) var isScanning = false
    var errorText: String?
    private(set) var needsReauthorization = false

    init(environment: AppEnvironment, library: CategoryLibrary) {
        self.environment = environment
        self.library = library
    }

    func restoreSavedFolder() async {
        guard !didRestore else { return }
        didRestore = true
        do {
            guard let folder = try environment.sourceFolders.load(), let bookmark = folder.bookmarkData else { return }
            savedFolder = folder
            await scan(bookmarkData: bookmark, replacingSavedFolder: false)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func chooseFolderAndScan() async {
        let picked = FolderPicker.chooseDirectory(startingAt: FolderPicker.downloadsDirectory)
        guard let picked else { return }
        do {
            let bookmark = try environment.permissions.createBookmark(for: picked)
            let folder = SourceFolder(
                id: savedFolder?.id ?? UUID(),
                displayName: picked.lastPathComponent,
                bookmarkData: bookmark,
                ruleSetID: savedFolder?.ruleSetID ?? UUID(),
                mode: savedFolder?.mode ?? .existingAndNew,
                isActive: true
            )
            savedFolder = folder
            try environment.sourceFolders.save(folder)
            await scan(bookmarkData: bookmark, replacingSavedFolder: true)
        } catch {
            rows = []
            folderPath = nil
            needsReauthorization = error is PermissionError
            errorText = error.localizedDescription
        }
    }

    private func scan(bookmarkData: Data, replacingSavedFolder: Bool) async {
        isScanning = true
        errorText = nil
        needsReauthorization = false
        defer { isScanning = false }

        let permissions = environment.permissions
        let scope = environment.securityScope
        let scanner = environment.scanner
        let store = environment.sourceFolders
        let categories = library.categories

        do {
            let access = try permissions.resolve(bookmarkData, scope: scope)
            defer { scope.stopAccessing(access.url) }
            if access.didRefreshStaleBookmark, var folder = savedFolder {
                folder.bookmarkData = access.bookmarkData
                try store.save(folder)
                savedFolder = folder
            }
            let source = access.url
            let scanned = try await Task.detached {
                try scanner.scanAll(source: source)
            }.value
            snapshots = scanned
            sourceURL = source
            rows = Self.rows(from: scanned, categories: categories, sourceRoot: source)
            folderPath = source.path(percentEncoded: false)
            needsReauthorization = false
        } catch {
            if !replacingSavedFolder {
                savedFolder = nil
            }
            snapshots = []
            sourceURL = nil
            rows = []
            folderPath = nil
            needsReauthorization = error is PermissionError
            errorText = error.localizedDescription
        }
    }

    func rescan() async {
        guard let bookmark = savedFolder?.bookmarkData else { return }
        await scan(bookmarkData: bookmark, replacingSavedFolder: true)
    }

    func reclassify() {
        guard let sourceURL else { return }
        rows = Self.rows(from: snapshots, categories: library.categories, sourceRoot: sourceURL)
    }

    private nonisolated static func rows(
        from snapshots: [FileSnapshot],
        categories: [OrganizerCategory],
        sourceRoot: URL
    ) -> [ScannedFile] {
        let engine = ClassificationEngine(categories: categories)
        return snapshots.map { snapshot in
            let classification = engine.classify(snapshot, sourceRoot: sourceRoot)
            return ScannedFile(
                url: snapshot.url,
                name: snapshot.name,
                categoryName: classification?.category.name ?? "Uncategorized",
                destinationPath: relativeDestination(classification?.explanation.destinationURL, sourceRoot: sourceRoot)
            )
        }
    }

    private nonisolated static func relativeDestination(_ destination: URL?, sourceRoot: URL) -> String {
        guard let destination else { return "" }
        let root = sourceRoot.standardizedFileURL.path
        let full = destination.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard full.hasPrefix(prefix) else { return full }
        return String(full.dropFirst(prefix.count))
    }
}
