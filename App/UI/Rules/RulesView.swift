import DownloadOrganizerCore
import SwiftUI

struct RulesView: View {
    @Bindable var model: RulesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let banner = model.banner {
                Label(banner, systemImage: model.isReadOnly ? "lock" : "exclamationmark.triangle")
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
            }
            if let sampleSummary = model.sampleSummary {
                Text(sampleSummary)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4))
                    .accessibilityLabel(sampleSummary)
            }
            list
        }
        .navigationTitle("Rules")
        .toolbar { toolbar }
        .sheet(item: $model.editor) { editor in
            RuleEditorView(editor: editor, model: model)
        }
        .confirmationDialog(
            "Delete this category?",
            isPresented: $model.confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.confirmDeleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The category is removed from the list. Files already moved stay where they are.")
        }
        .confirmationDialog(
            "Apply \(model.pendingPreset?.title ?? "preset")?",
            isPresented: presetPresented,
            titleVisibility: .visible
        ) {
            Button("Replace Categories") { model.applyPending(mode: .replace) }
            Button("Merge") { model.applyPending(mode: .merge) }
            Button("Cancel", role: .cancel) { model.pendingPreset = nil }
        } message: {
            Text(model.pendingPreset?.summary ?? "You can replace the list or add categories that are not already there.")
        }
        .alert(
            "Could Not Update Rules",
            isPresented: Binding(
                get: { model.errorText != nil },
                set: { isPresented in
                    if !isPresented { model.errorText = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorText ?? "")
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            Section("Priority") {
                ForEach(model.specific) { category in
                    row(category, warnings: warningsByCategory[category.id] ?? [])
                        .tag(category.id)
                }
                .onMove { offsets, destination in
                    model.move(from: offsets, to: destination)
                }
            }
            Section("Catch-all, always last") {
                ForEach(model.catchAlls) { category in
                    row(category, warnings: warningsByCategory[category.id] ?? [])
                        .tag(category.id)
                }
            }
        }
        .accessibilityLabel("Categories in priority order")
        .overlay {
            if model.categories.isEmpty {
                ContentUnavailableView("No Categories", systemImage: "list.bullet", description: Text("Add a category or apply a preset."))
            }
        }
    }

    private var warningsByCategory: [UUID: [OverlapWarning]] {
        Dictionary(grouping: OverlapDetector().detect(categories: model.categories), by: \.categoryID)
    }

    private func row(_ category: OrganizerCategory, warnings: [OverlapWarning]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: category.iconSymbol)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.headline)
                Text(RuleSummary.listSummary(for: category))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(category.destination.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(warning.message)
                }
            }
            Spacer(minLength: 8)
            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { category.enabled },
                    set: { model.setEnabled(id: category.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .disabled(model.isReadOnly)
            .accessibilityLabel("\(category.name) enabled")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .draggable(category.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = UUID(uuidString: raw), !category.isCatchAll else { return false }
            model.drop(dragged, onto: category.id)
            return true
        }
        .contextMenu {
            Button("Edit") { model.edit(category.id) }
            Button("Duplicate") { model.selection = category.id; model.duplicateSelected() }
            Button("Test") { model.edit(category.id) }
            Divider()
            Button("Move Up") { model.selection = category.id; model.moveSelected(direction: -1) }
                .disabled(category.isCatchAll)
            Button("Move Down") { model.selection = category.id; model.moveSelected(direction: 1) }
                .disabled(category.isCatchAll)
            Divider()
            Button("Delete", role: .destructive) {
                model.selection = category.id
                model.deleteSelected()
            }
        }
        .accessibilityAction(named: "Move Up") { model.move(id: category.id, direction: -1) }
        .accessibilityAction(named: "Move Down") { model.move(id: category.id, direction: 1) }
        .onTapGesture(count: 2) { model.edit(category.id) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Add", systemImage: "plus") { model.addCategory() }
                .disabled(model.isReadOnly)
                .accessibilityLabel("New category")
                .accessibilityHint("Keyboard shortcut Command N.")
            Button("Edit") { model.editSelected() }
                .disabled(model.selection == nil)
            Button("Duplicate") { model.duplicateSelected() }
                .disabled(model.selection == nil || model.isReadOnly)
            Button("Delete", systemImage: "trash") { model.deleteSelected() }
                .disabled(model.selection == nil || model.isReadOnly)
                .keyboardShortcut(.delete, modifiers: .command)
            Button("Test") { model.editSelected() }
                .disabled(model.selection == nil)
                .accessibilityHint("Opens the category and the Test Rule panel.")
            Button("Check Sample") { model.chooseSampleFile() }
                .accessibilityHint("Uses a real file to see which categories match. Overlap warnings are best-effort.")
            Menu("Presets") {
                ForEach(CategoryPreset.allCases) { preset in
                    Button(preset.title) { model.pendingPreset = preset }
                }
            }
            .disabled(model.isReadOnly)
            .accessibilityLabel("Apply a preset")
        }
    }

    private var presetPresented: Binding<Bool> {
        Binding(
            get: { model.pendingPreset != nil },
            set: { isPresented in
                if !isPresented { model.pendingPreset = nil }
            }
        )
    }
}
