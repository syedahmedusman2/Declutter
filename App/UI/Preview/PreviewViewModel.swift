import DeclutterCore
import Foundation
import Observation

struct PreviewRow: Identifiable {
    var id: UUID
    var fileName: String
    var currentLocation: String
    var categoryName: String
    var destination: String
    var rule: String
    var action: String
    var conflict: String
    var message: String
}

struct PreviewProblem: Identifiable {
    var id: String
    var name: String
    var message: String
    var isFailure: Bool
}

@MainActor
@Observable
final class PreviewViewModel {
    private let environment: AppEnvironment
    private let library: CategoryLibrary

    private var moves: [PlannedMove] = []
    private var sourceRoot: URL?
    private var plannerOptions = OrganizeOptions()
    private var accessedURLs: [URL] = []
    private var execution: OrganizeExecution?
    private var suppressStale = false

    var onOrganized: (@MainActor () async -> Void)?
    var globalConflictPolicy: ConflictPolicy = .autoRename
    var moveSymlinks = false
    var bulkConfirmationThreshold = 50
    private(set) var needsReauthorization = false

    private(set) var folderPath: String?
    private(set) var isPlanning = false
    private(set) var isExecuting = false
    private(set) var planIsStale = false
    private(set) var summary: String?
    private(set) var problems: [PreviewProblem] = []
    private(set) var progressFraction = 0.0
    private(set) var progressText = ""
    private(set) var progressCount = ""

    var errorText: String?
    var search = ""
    var categoryFilter = ""
    var conflictFilter: ConflictStatus?
    var selection = Set<PreviewRow.ID>()
    var showConfirmation = false
    var confirmDetail = ""

    init(environment: AppEnvironment, library: CategoryLibrary) {
        self.environment = environment
        self.library = library
    }

    var filteredRows: [PreviewRow] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return moves.compactMap { move in
            let row = Self.row(for: move, sourceRoot: sourceRoot)
            if !categoryFilter.isEmpty, row.categoryName != categoryFilter { return nil }
            if let conflictFilter, move.conflict != conflictFilter { return nil }
            guard !query.isEmpty else { return row }
            let haystack = [row.fileName, row.currentLocation, row.categoryName, row.destination, row.rule, row.message]
                .joined(separator: "\n")
            return haystack.localizedCaseInsensitiveContains(query) ? row : nil
        }
    }

    var categoryNames: [String] {
        Array(Set(moves.map { Self.categoryName($0) })).sorted()
    }

    var hasMoves: Bool { !moves.isEmpty }

    var canExecute: Bool {
        !selection.isEmpty && !isPlanning && !isExecuting && !planIsStale && sourceRoot != nil
    }

    func refreshIfNeeded() async {
        guard moves.isEmpty || planIsStale else { return }
        await refresh()
    }

    func markStale() {
        guard !suppressStale, !moves.isEmpty else { return }
        planIsStale = true
    }

    func refresh() async {
        guard !isPlanning, !isExecuting else { return }
        isPlanning = true
        suppressStale = true
        errorText = nil
        summary = nil
        problems = []
        showConfirmation = false
        defer {
            isPlanning = false
            Task { @MainActor in
                suppressStale = false
            }
        }
        releaseAccess()

        do {
            guard let folder = try environment.sourceFolders.load(), let bookmark = folder.bookmarkData else {
                moves = []
                sourceRoot = nil
                folderPath = nil
                selection = []
                errorText = "Choose a folder on the Files screen first."
                return
            }
            let access = try environment.permissions.resolve(bookmark, scope: environment.securityScope)
            retain(access.url)
            if access.didRefreshStaleBookmark {
                var updated = folder
                updated.bookmarkData = access.bookmarkData
                try environment.sourceFolders.save(updated)
            }

            let roots = destinationRoots(source: access.url)
            let categories = library.categories
            let scanner = environment.scanner
            let fileSystem = environment.fileSystem
            let source = access.url
            let options = OrganizeOptions(
                globalConflictPolicy: globalConflictPolicy,
                permittedRoots: roots,
                bulkConfirmationThreshold: bulkConfirmationThreshold,
                moveSymlinks: moveSymlinks
            )
            let files = try await Task.detached {
                try scanner.scanAll(source: source)
            }.value
            let planned = await Task.detached {
                OrganizePlanner(
                    fileSystem: fileSystem,
                    categories: categories,
                    sourceRoot: source,
                    options: options
                ).plan(files: files)
            }.value

            moves = planned
            sourceRoot = source
            folderPath = source.path(percentEncoded: false)
            plannerOptions = options
            planIsStale = false
            selection = Set(planned.filter { $0.action == .move || $0.action == .replace }.map(\.id))
            needsReauthorization = false
        } catch {
            releaseAccess()
            moves = []
            sourceRoot = nil
            folderPath = nil
            selection = []
            needsReauthorization = error is PermissionError
            errorText = error.localizedDescription
        }
    }

    func selectAll() {
        selection = Set(filteredRows.map(\.id))
    }

    func selectNone() {
        selection = []
    }

    func apply(_ policy: ConflictPolicy, to ids: Set<PreviewRow.ID>) async {
        guard let sourceRoot, !ids.isEmpty, !isExecuting else { return }
        let current = moves
        let options = plannerOptions
        let categories = library.categories
        let fileSystem = environment.fileSystem
        let updated = await Task.detached {
            let planner = OrganizePlanner(
                fileSystem: fileSystem,
                categories: categories,
                sourceRoot: sourceRoot,
                options: options
            )
            var next = current
            for id in ids {
                guard let index = next.firstIndex(where: { $0.id == id }) else { continue }
                next[index] = planner.applying(policy: policy, to: next[index])
            }
            return next
        }.value
        moves = updated
    }

    func requestExecute() {
        let chosen = selectedMoves()
        guard !chosen.isEmpty, canExecute else { return }
        let replaceCount = chosen.filter { $0.action == .replace }.count
        if chosen.count >= plannerOptions.bulkConfirmationThreshold || replaceCount > 0 {
            confirmDetail = Self.confirmText(count: chosen.count, replaceCount: replaceCount, threshold: plannerOptions.bulkConfirmationThreshold)
            showConfirmation = true
        } else {
            Task { await performExecute() }
        }
    }

    func performExecute() async {
        guard let sourceRoot, canExecute else { return }
        let chosen = selectedMoves()
        guard !chosen.isEmpty else { return }
        let replacing = chosen.contains { $0.action == .replace }
        let ids = selection
        isExecuting = true
        progressFraction = 0
        progressText = "Starting"
        progressCount = "0 of \(chosen.count)"
        summary = nil
        problems = []

        let execution = environment.organizer.execute(
            plan: moves,
            selection: ids,
            sourceRoot: sourceRoot,
            options: plannerOptions,
            replaceConfirmed: replacing
        )
        self.execution = execution
        let progressTask = Task {
            for await update in execution.progress {
                let total = update.total
                progressFraction = total == 0 ? 0 : Double(update.completed) / Double(total)
                progressText = update.fileName.isEmpty ? "Starting" : update.fileName
                progressCount = "\(update.completed) of \(total)"
            }
        }
        let batch = await execution.result.value
        await progressTask.value
        self.execution = nil
        summary = Self.summary(for: batch)
        problems = Self.problems(in: batch)
        planIsStale = true
        isExecuting = false
        await onOrganized?()
        releaseAccess()
    }

    func cancelExecute() {
        execution?.cancel()
    }

    private func selectedMoves() -> [PlannedMove] {
        moves.filter { selection.contains($0.id) }
    }

    private func destinationRoots(source: URL) -> [URL] {
        var roots = [source]
        for category in library.categories {
            guard case .absolute(let path, let bookmark) = category.destination else { continue }
            guard let bookmark else {
                roots.append(URL(fileURLWithPath: path))
                continue
            }
            do {
                let access = try environment.permissions.resolve(bookmark, scope: environment.securityScope)
                retain(access.url)
                roots.append(access.url)
                if access.didRefreshStaleBookmark {
                    var updated = category
                    updated.destination = .absolute(
                        path: access.url.path(percentEncoded: false),
                        bookmark: access.bookmarkData
                    )
                    updated.updatedAt = Date()
                    library.upsert(updated, isNew: false)
                }
            } catch {
                CoreLog.organizer.error(
                    "Could not open destination \(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                roots.append(URL(fileURLWithPath: path))
            }
        }
        return roots
    }

    private func retain(_ url: URL) {
        accessedURLs.append(url)
    }

    private func releaseAccess() {
        for url in accessedURLs {
            environment.securityScope.stopAccessing(url)
        }
        accessedURLs.removeAll()
    }

    private static func row(for move: PlannedMove, sourceRoot: URL?) -> PreviewRow {
        PreviewRow(
            id: move.id,
            fileName: move.snapshot.name,
            currentLocation: displayPath(move.snapshot.url.deletingLastPathComponent(), sourceRoot: sourceRoot),
            categoryName: categoryName(move),
            destination: displayPath(move.proposedURL, sourceRoot: sourceRoot),
            rule: move.ruleSummary.isEmpty ? "—" : move.ruleSummary,
            action: actionLabel(move.action),
            conflict: conflictLabel(move.conflict),
            message: move.message
        )
    }

    private static func categoryName(_ move: PlannedMove) -> String {
        move.categoryName.isEmpty ? "Uncategorized" : move.categoryName
    }

    static func actionLabel(_ action: PlannedAction) -> String {
        switch action {
        case .move: "Move"
        case .skip: "Skip"
        case .replace: "Replace"
        case .needsDecision: "Needs a decision"
        case .blocked: "Blocked"
        }
    }

    static func conflictLabel(_ status: ConflictStatus) -> String {
        switch status {
        case .none: "None"
        case .autoRename: "Auto rename"
        case .skip: "Skip"
        case .replace: "Replace"
        case .needsDecision: "Needs a decision"
        case .blocked: "Blocked"
        }
    }

    private static func displayPath(_ url: URL, sourceRoot: URL?) -> String {
        let full = url.path(percentEncoded: false)
        guard let sourceRoot else { return full }
        let root = sourceRoot.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if path == root { return "." }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return full }
        return String(path.dropFirst(prefix.count))
    }

    private static func confirmText(count: Int, replaceCount: Int, threshold: Int) -> String {
        var lines: [String] = []
        if count >= threshold {
            lines.append("\(count) files are selected.")
        }
        if replaceCount > 0 {
            let noun = replaceCount == 1 ? "file" : "files"
            lines.append("\(replaceCount) existing \(noun) will be moved to the Trash.")
        }
        return lines.joined(separator: " ")
    }

    private static func summary(for batch: BatchResult) -> String {
        let prefix = batch.cancelled ? "Cancelled. " : ""
        return "\(prefix)Moved \(batch.succeeded). Skipped \(batch.skipped). Failed \(batch.failed). Needs a decision \(batch.needsDecision)."
    }

    private static func problems(in batch: BatchResult) -> [PreviewProblem] {
        let notable = batch.results.filter { $0.status == .failed || $0.status == .needsDecision }
        let shown = notable.prefix(40)
        var rows = shown.map { result in
            PreviewProblem(
                id: "\(result.sourceURL.path)-\(result.status.rawValue)",
                name: result.sourceURL.lastPathComponent,
                message: result.message,
                isFailure: result.status == .failed
            )
        }
        if notable.count > shown.count {
            rows.append(
                PreviewProblem(
                    id: "more",
                    name: "More",
                    message: "\(notable.count - shown.count) more files",
                    isFailure: false
                )
            )
        }
        return rows
    }
}
