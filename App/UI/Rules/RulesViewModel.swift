import DeclutterCore
import Foundation
import Observation

@MainActor
@Observable
final class CategoryEditorModel: Identifiable {
    let id: UUID
    var isNew: Bool
    var name: String
    var iconSymbol: String
    var enabled: Bool
    var isCatchAll: Bool
    var destinationIsAbsolute: Bool
    var relativePath: String
    var absolutePath: String
    var absoluteBookmark: Data?
    var extensions: [String]
    var extensionDraft = ""
    var advanced: RuleNode?
    var conflictPolicy: ConflictPolicy?
    var createdAt: Date
    var sourcePath: String?
    var matchCountText = "Choose a folder on the Files screen to count matches."
    var testReport: RuleTestReport?
    var testFileName: String?
    var testError: String?

    init(
        id: UUID,
        isNew: Bool,
        name: String,
        iconSymbol: String,
        enabled: Bool,
        isCatchAll: Bool,
        destinationIsAbsolute: Bool,
        relativePath: String,
        absolutePath: String,
        absoluteBookmark: Data?,
        extensions: [String],
        advanced: RuleNode?,
        conflictPolicy: ConflictPolicy?,
        createdAt: Date
    ) {
        self.id = id
        self.isNew = isNew
        self.name = name
        self.iconSymbol = iconSymbol
        self.enabled = enabled
        self.isCatchAll = isCatchAll
        self.destinationIsAbsolute = destinationIsAbsolute
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.absoluteBookmark = absoluteBookmark
        self.extensions = extensions
        self.advanced = advanced
        self.conflictPolicy = conflictPolicy
        self.createdAt = createdAt
    }

    var trimmedIcon: String {
        let trimmed = iconSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "folder" : trimmed
    }

    var regexIssues: [RuleIssue] {
        guard let advanced, !isCatchAll else { return [] }
        return RuleValidator.issues(in: advanced)
    }

    var destinationWarning: String? {
        if destinationIsAbsolute {
            let path = absolutePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            guard let sourcePath, !sourcePath.isEmpty else {
                return "This folder is outside the source folder until a source folder is chosen. A bookmark is saved with the category."
            }
            let prefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
            if path == sourcePath || path.hasPrefix(prefix) { return nil }
            return "This folder is outside the source folder. A bookmark is saved so the app can write there later."
        }
        if relativePath.split(separator: "/").contains("..") {
            return "The destination has to stay inside the source folder."
        }
        return nil
    }

    var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, regexIssues.isEmpty else { return false }
        guard destinationIsReady else { return false }
        if isCatchAll { return true }
        // Empty AND matches every file. Non-catch-all categories need at least one real condition.
        return hasMatchingRule
    }

    var saveBlockedReason: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Give the category a name."
        }
        if !regexIssues.isEmpty {
            return "Fix the regular expression before saving."
        }
        if !destinationIsReady {
            return destinationIsAbsolute
                ? "Choose a destination folder."
                : "Enter a folder name inside the source folder."
        }
        if !isCatchAll && !hasMatchingRule {
            return "Add at least one extension or condition. A category with no rule would match every file."
        }
        return nil
    }

    private var destinationIsReady: Bool {
        if destinationIsAbsolute {
            return !absolutePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && absoluteBookmark != nil
        }
        let relative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !relative.isEmpty && !relative.split(separator: "/").contains("..")
    }

    private var hasMatchingRule: Bool {
        let rule = RuleComposer.compose(extensions: extensions, advanced: advanced, catchAll: false)
        if case .group(.and, let children) = rule, children.isEmpty {
            return false
        }
        return true
    }

    var ruleSignature: String {
        let rule = RuleComposer.compose(extensions: extensions, advanced: advanced, catchAll: isCatchAll)
        let data = (try? JSONEncoder().encode(rule)) ?? Data()
        return data.base64EncodedString()
    }

    func addExtension() {
        let cleaned = extensionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = cleaned.hasPrefix(".") ? String(cleaned.dropFirst()) : cleaned
        guard !value.isEmpty else { return }
        if !extensions.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            extensions.append(value)
        }
        extensionDraft = ""
    }

    func removeExtension(_ value: String) {
        extensions.removeAll { $0 == value }
    }

    func addCondition() {
        append(.condition(Condition(field: .filename, op: .contains, value: "")))
    }

    func addGroup() {
        append(.group(.and, [.condition(Condition(field: .filename, op: .contains, value: ""))]))
    }

    func makeCategory() -> OrganizerCategory {
        let destination: Destination
        if destinationIsAbsolute {
            destination = .absolute(path: absolutePath, bookmark: absoluteBookmark)
        } else {
            destination = .relative(relativePath.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let icon = trimmedIcon
        return OrganizerCategory(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            iconSymbol: icon,
            destination: destination,
            enabled: enabled,
            priority: 0,
            rule: RuleComposer.compose(extensions: extensions, advanced: advanced, catchAll: isCatchAll),
            conflictPolicy: conflictPolicy,
            action: .move,
            isCatchAll: isCatchAll,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    private func append(_ node: RuleNode) {
        switch advanced {
        case nil:
            advanced = node
        case .condition:
            advanced = .group(.and, [advanced!, node])
        case .group(let op, let children):
            advanced = .group(op, children + [node])
        }
    }
}

@MainActor
@Observable
final class RulesViewModel {
    private let environment: AppEnvironment
    private let library: CategoryLibrary

    var selection: UUID?
    var editor: CategoryEditorModel?
    var confirmDelete = false
    var pendingPreset: CategoryPreset?
    var sampleSummary: String?
    var errorText: String?

    init(environment: AppEnvironment, library: CategoryLibrary) {
        self.environment = environment
        self.library = library
    }

    var isReadOnly: Bool { library.isReadOnly }
    var banner: String? { library.message }
    var categories: [OrganizerCategory] { library.categories }
    var specific: [OrganizerCategory] { categories.filter { !$0.isCatchAll } }
    var catchAlls: [OrganizerCategory] { categories.filter(\.isCatchAll) }

    func addCategory() {
        guard !isReadOnly else { return }
        editor = CategoryEditorModel(
            id: UUID(),
            isNew: true,
            name: "New Category",
            iconSymbol: "folder",
            enabled: true,
            isCatchAll: false,
            destinationIsAbsolute: false,
            relativePath: "New Category",
            absolutePath: "",
            absoluteBookmark: nil,
            extensions: [],
            advanced: nil,
            conflictPolicy: nil,
            createdAt: Date()
        )
        Task { await loadSourcePath() }
    }

    func edit(_ id: UUID) {
        guard let category = categories.first(where: { $0.id == id }) else { return }
        selection = id
        let model = CategoryEditorModel(
            id: category.id,
            isNew: false,
            name: category.name,
            iconSymbol: category.iconSymbol,
            enabled: category.enabled,
            isCatchAll: category.isCatchAll,
            destinationIsAbsolute: category.destination.isAbsolute,
            relativePath: category.destination.isAbsolute ? category.name : category.destination.path,
            absolutePath: category.destination.isAbsolute ? category.destination.path : "",
            absoluteBookmark: bookmark(from: category.destination),
            extensions: category.isCatchAll ? [] : RuleComposer.primaryExtensions(in: category.rule),
            advanced: category.isCatchAll ? nil : RuleComposer.advancedRule(in: category.rule),
            conflictPolicy: category.conflictPolicy,
            createdAt: category.createdAt
        )
        editor = model
        Task { await loadSourcePath() }
    }

    func editSelected() {
        guard let selection else { return }
        edit(selection)
    }

    func duplicateSelected() {
        guard let selection else { return }
        library.duplicate(id: selection)
    }

    func deleteSelected() {
        guard selection != nil else { return }
        confirmDelete = true
    }

    func confirmDeleteSelected() {
        guard let selection else { return }
        library.delete(id: selection)
        self.selection = nil
        confirmDelete = false
    }

    func move(from offsets: IndexSet, to destination: Int) {
        library.move(from: offsets, to: destination)
    }

    func drop(_ draggedID: UUID, onto targetID: UUID) {
        guard draggedID != targetID else { return }
        var items = specific
        guard let from = items.firstIndex(where: { $0.id == draggedID }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        library.replaceOrder(items.map(\.id))
    }

    func moveSelected(direction: Int) {
        guard let selection else { return }
        library.move(id: selection, direction: direction)
    }

    func move(id: UUID, direction: Int) {
        library.move(id: id, direction: direction)
    }

    func setEnabled(id: UUID, enabled: Bool) {
        library.setEnabled(id: id, enabled: enabled)
    }

    func saveEditor() {
        guard let editor, editor.canSave, !isReadOnly else { return }
        library.upsert(editor.makeCategory(), isNew: editor.isNew)
        selection = editor.id
        self.editor = nil
    }

    func applyPending(mode: PresetApplyMode) {
        guard let pendingPreset else { return }
        library.apply(preset: pendingPreset, mode: mode)
        self.pendingPreset = nil
    }

    func chooseAbsoluteDestination() {
        guard let editor else { return }
        guard let picked = FolderPicker.chooseDestination(startingAt: FolderPicker.downloadsDirectory) else { return }
        do {
            editor.absoluteBookmark = try environment.permissions.createBookmark(for: picked)
            editor.absolutePath = picked.path(percentEncoded: false)
            editor.destinationIsAbsolute = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    func chooseTestFile() {
        guard let url = FolderPicker.chooseFile() else { return }
        Task { await testFile(at: url) }
    }

    func chooseSampleFile() {
        guard let url = FolderPicker.chooseFile() else { return }
        Task { await checkSample(at: url) }
    }

    func refreshMatchCount() async {
        guard let editor else { return }
        let signature = editor.ruleSignature
        let text = await matchCountText(for: editor)
        guard !Task.isCancelled, editor.ruleSignature == signature else { return }
        editor.matchCountText = text
    }

    func testFile(at url: URL) async {
        guard let editor else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let loader = environment.snapshotLoader
            let snapshot = try await Task.detached {
                try loader.load(url: url)
            }.value
            let source = (try? await sourceURL()) ?? url.deletingLastPathComponent()
            guard let placed = placedDraft(editor) else { return }
            let report = ClassificationEngine(categories: previewCategories(including: placed))
                .testRule(placed, file: snapshot, sourceRoot: source)
            editor.testReport = report
            editor.testFileName = snapshot.name
            editor.testError = nil
        } catch {
            editor.testError = error.localizedDescription
            editor.testReport = nil
        }
    }

    func checkSample(at url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let loader = environment.snapshotLoader
            let snapshot = try await Task.detached {
                try loader.load(url: url)
            }.value
            sampleSummary = OverlapDetector().check(file: snapshot, categories: categories).summary
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func matchCountText(for editor: CategoryEditorModel) async -> String {
        do {
            guard let scanned = try await scanSource() else {
                return "Choose a folder on the Files screen to count matches."
            }
            guard let placed = placedDraft(editor) else {
                return "Matches could not be counted."
            }
            let files = scanned.files
            let rules = RuleEngine()
            let preview = previewCategories(including: placed)
            let count: Int
            if placed.isCatchAll {
                let specific = preview.filter { $0.enabled && !$0.isCatchAll }
                count = files.filter { file in
                    !specific.contains { rules.evaluate($0.rule, file: file).passed }
                }.count
            } else {
                count = files.filter { rules.evaluate(placed.rule, file: $0).passed }.count
            }
            let noun = count == 1 ? "file" : "files"
            if placed.isCatchAll {
                return "Would receive \(count) \(noun) in your folder."
            }
            return "Matches \(count) \(noun) in your folder."
        } catch {
            return "Matches could not be counted. \(error.localizedDescription)"
        }
    }

    private func scanSource() async throws -> (url: URL, files: [FileSnapshot])? {
        let store = environment.sourceFolders
        let permissions = environment.permissions
        let scope = environment.securityScope
        let scanner = environment.scanner
        let folder = try await Task.detached {
            try store.load()
        }.value
        guard let bookmark = folder?.bookmarkData else { return nil }
        let access = try permissions.resolve(bookmark, scope: scope)
        defer { scope.stopAccessing(access.url) }
        let files = try await Task.detached {
            try scanner.scanAll(source: access.url)
        }.value
        return (access.url, files)
    }

    private func loadSourcePath() async {
        guard let editor else { return }
        editor.sourcePath = try? await sourceURL()?.path(percentEncoded: false)
    }

    private func sourceURL() async throws -> URL? {
        let store = environment.sourceFolders
        let permissions = environment.permissions
        let scope = environment.securityScope
        let folder = try await Task.detached {
            try store.load()
        }.value
        guard let bookmark = folder?.bookmarkData else { return nil }
        let access = try permissions.resolve(bookmark, scope: scope)
        scope.stopAccessing(access.url)
        return access.url
    }

    private func placedDraft(_ editor: CategoryEditorModel) -> OrganizerCategory? {
        previewCategories(including: editor.makeCategory()).first { $0.id == editor.id }
    }

    private func previewCategories(including draft: OrganizerCategory) -> [OrganizerCategory] {
        var next = categories.filter { $0.id != draft.id }
        if draft.isCatchAll {
            next.append(draft)
        } else if editor?.isNew == true {
            next.insert(draft, at: 0)
        } else if let index = categories.firstIndex(where: { $0.id == draft.id }) {
            let insertAt = categories.prefix(index).filter { !$0.isCatchAll }.count
            var specific = next.filter { !$0.isCatchAll }
            specific.insert(draft, at: min(insertAt, specific.count))
            next = specific + next.filter(\.isCatchAll)
        } else {
            next.insert(draft, at: 0)
        }
        return next.enumerated().map { offset, category in
            var copy = category
            copy.priority = offset
            return copy
        }
    }

    private func bookmark(from destination: Destination) -> Data? {
        if case .absolute(_, let bookmark) = destination { return bookmark }
        return nil
    }
}
