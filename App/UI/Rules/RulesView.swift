import DeclutterCore
import SwiftUI

struct RulesView: View {
    @Bindable var model: RulesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let banner = model.banner {
                HStack(spacing: 8) {
                    Image(systemName: model.isReadOnly ? "lock.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.isReadOnly ? Color.secondary : Color.orange)
                    Text(banner)
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.5))
                Divider()
            }

            if let sampleSummary = model.sampleSummary {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.gearshape.fill")
                        .foregroundStyle(.blue)
                    Text(sampleSummary)
                        .font(.callout)
                    Spacer()
                    Button("Clear") {
                        model.sampleSummary = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.blue.opacity(0.08))
                Divider()
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
            if !model.specific.isEmpty {
                Section {
                    ForEach(model.specific) { category in
                        row(category, warnings: warningsByCategory[category.id] ?? [])
                            .tag(category.id)
                    }
                    .onMove { offsets, destination in
                        model.move(from: offsets, to: destination)
                    }
                } header: {
                    HStack {
                        Text("PRIORITY RULES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Evaluated top-to-bottom")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
            }

            if !model.catchAlls.isEmpty {
                Section {
                    ForEach(model.catchAlls) { category in
                        row(category, warnings: warningsByCategory[category.id] ?? [])
                            .tag(category.id)
                    }
                } header: {
                    HStack {
                        Text("CATCH-ALL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Always evaluated last")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .accessibilityLabel("Categories in priority order")
        .overlay {
            if model.categories.isEmpty {
                ContentUnavailableView(
                    "No Categories",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add a category or apply a preset to begin sorting files.")
                )
            }
        }
    }

    private var warningsByCategory: [UUID: [OverlapWarning]] {
        Dictionary(grouping: OverlapDetector().detect(categories: model.categories), by: \.categoryID)
    }

    private func categoryColor(for category: OrganizerCategory) -> Color {
        let name = category.name.lowercased()
        if name.contains("image") || name.contains("photo") { return .purple }
        if name.contains("video") || name.contains("movie") { return .pink }
        if name.contains("music") || name.contains("audio") { return .red }
        if name.contains("archive") || name.contains("zip") { return .orange }
        if name.contains("doc") || name.contains("pdf") || name.contains("word") { return .blue }
        if name.contains("text") { return .indigo }
        if name.contains("code") || name.contains("developer") { return .teal }
        if name.contains("sheet") || name.contains("excel") || name.contains("number") { return .green }
        return .cyan
    }

    private func row(_ category: OrganizerCategory, warnings: [OverlapWarning]) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon Pill
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(categoryColor(for: category).gradient)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: category.iconSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: categoryColor(for: category).opacity(0.2), radius: 2, y: 1)
                .accessibilityHidden(true)

            // Texts & Metadata
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(category.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(category.enabled ? .primary : .secondary)

                    if category.isCatchAll {
                        Text("Catch-All")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(RuleSummary.listSummary(for: category))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(category.destination.path, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(warnings) { warning in
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(warning.message)
                        }
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(warning.message)
                    }
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
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(model.isReadOnly)
            .accessibilityLabel("\(category.name) enabled")
        }
        .padding(.vertical, 6)
        .opacity(category.enabled ? 1.0 : 0.55)
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
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.addCategory()
            } label: {
                Label("Add Category", systemImage: "plus")
            }
            .disabled(model.isReadOnly)
            .help("Create new category (⌘N)")

            Button {
                model.editSelected()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(model.selection == nil)
            .help("Edit selected rule")

            Button {
                model.duplicateSelected()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(model.selection == nil || model.isReadOnly)
            .help("Duplicate selected rule")

            Button(role: .destructive) {
                model.deleteSelected()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(model.selection == nil || model.isReadOnly)
            .keyboardShortcut(.delete, modifiers: .command)
            .help("Delete selected rule (⌘Delete)")

            Button {
                model.chooseSampleFile()
            } label: {
                Label("Check Sample", systemImage: "doc.badge.gearshape")
            }
            .help("Test a real file to see which rule matches")

            Menu {
                ForEach(CategoryPreset.allCases) { preset in
                    Button(preset.title) { model.pendingPreset = preset }
                }
            } label: {
                Label("Presets", systemImage: "slider.horizontal.3")
            }
            .disabled(model.isReadOnly)
            .help("Apply a rule preset")
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
