import DownloadOrganizerCore
import Foundation
import Observation

typealias OrganizerCategory = DownloadOrganizerCore.Category

@MainActor
@Observable
final class CategoryLibrary {
    private let store: CategoryStore
    private(set) var categories: [OrganizerCategory] = []
    private(set) var isReadOnly = false
    private(set) var message: String?
    private var loadedSchemaVersion: Int?
    private(set) var isLoaded = false

    init(store: CategoryStore) {
        self.store = store
    }

    func load() async {
        let store = store
        do {
            let stored = try await Task.detached {
                try store.load()
            }.value
            if let stored {
                categories = stored.categories
                isReadOnly = stored.isReadOnly
                message = stored.message
                loadedSchemaVersion = stored.schemaVersion
            } else {
                categories = DefaultCategories.make()
                loadedSchemaVersion = SchemaVersion.current
                isReadOnly = false
                try await persist()
            }
        } catch {
            categories = DefaultCategories.make()
            isReadOnly = true
            message = error.localizedDescription
        }
        isLoaded = true
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard !isReadOnly, let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].enabled = enabled
        categories[index].updatedAt = Date()
        persistLater()
    }

    func upsert(_ category: OrganizerCategory, isNew: Bool) {
        guard !isReadOnly else { return }
        var next = categories
        if let index = next.firstIndex(where: { $0.id == category.id }) {
            next[index] = category
        } else if isNew {
            next.insert(category, at: 0)
        } else {
            next.append(category)
        }
        categories = normalized(next)
        persistLater()
    }

    func duplicate(id: UUID) {
        guard !isReadOnly, let index = categories.firstIndex(where: { $0.id == id }) else { return }
        var copy = categories[index]
        let now = Date()
        copy.id = UUID()
        copy.name = "\(copy.name) Copy"
        copy.createdAt = now
        copy.updatedAt = now
        var next = categories
        next.insert(copy, at: index + 1)
        categories = normalized(next)
        persistLater()
    }

    func delete(id: UUID) {
        guard !isReadOnly else { return }
        categories = normalized(categories.filter { $0.id != id })
        persistLater()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        guard !isReadOnly else { return }
        var specific = categories.filter { !$0.isCatchAll }
        specific.move(fromOffsets: offsets, toOffset: destination)
        categories = normalized(specific + categories.filter(\.isCatchAll))
        persistLater()
    }

    func replaceOrder(_ ids: [UUID]) {
        guard !isReadOnly else { return }
        let specific = categories.filter { !$0.isCatchAll }
        let byID = Dictionary(uniqueKeysWithValues: specific.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }
        let missing = specific.filter { !ids.contains($0.id) }
        categories = normalized(ordered + missing + categories.filter(\.isCatchAll))
        persistLater()
    }

    func move(id: UUID, direction: Int) {
        guard !isReadOnly else { return }
        var specific = categories.filter { !$0.isCatchAll }
        guard let index = specific.firstIndex(where: { $0.id == id }) else { return }
        let target = index + direction
        guard specific.indices.contains(target) else { return }
        specific.swapAt(index, target)
        categories = normalized(specific + categories.filter(\.isCatchAll))
        persistLater()
    }

    func replaceAll(_ incoming: [OrganizerCategory]) {
        guard !isReadOnly else { return }
        categories = normalized(incoming)
        persistLater()
    }

    func apply(preset: CategoryPreset, mode: PresetApplyMode) {
        guard !isReadOnly else { return }
        categories = CategoryPresets.apply(preset, to: categories, mode: mode)
        persistLater()
    }

    private func normalized(_ categories: [OrganizerCategory]) -> [OrganizerCategory] {
        let specific = categories.filter { !$0.isCatchAll }
        let catchAlls = categories.filter(\.isCatchAll)
        return (specific + catchAlls).enumerated().map { index, category in
            var copy = category
            copy.priority = index
            return copy
        }
    }

    private func persistLater() {
        Task { await persistSafely() }
    }

    private func persistSafely() async {
        do {
            try await persist()
            if !isReadOnly {
                message = nil
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func persist() async throws {
        let store = store
        let categories = categories
        let version = loadedSchemaVersion
        try await Task.detached {
            try store.save(categories, loadedSchemaVersion: version)
        }.value
    }
}
