import DownloadOrganizerCore
import SwiftUI

struct RuleEditorView: View {
    @Bindable var editor: CategoryEditorModel
    var model: RulesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HSplitView {
                form
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                TestRulePanel(editor: editor, model: model)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(editor.isNew ? "New Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.saveEditor() }
                        .disabled(!editor.canSave || model.isReadOnly)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint(editor.saveBlockedReason ?? "Saves this category and closes the editor.")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .task(id: editor.ruleSignature) {
            await model.refreshMatchCount()
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identity
                destination
                if !editor.isCatchAll {
                    extensions
                    whenSection
                }
                behavior
            }
            .padding(16)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $editor.name)
                .font(.title3)
                .accessibilityLabel("Category name")
            HStack {
                Image(systemName: editor.trimmedIcon)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                TextField("Icon symbol", text: $editor.iconSymbol)
                    .accessibilityLabel("Symbol name")
            }
            Toggle("Enabled", isOn: $editor.enabled)
            Toggle("Catch-all", isOn: $editor.isCatchAll)
                .accessibilityHint("Matches files that no earlier category takes. Catch-all categories are always evaluated last.")
        }
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination")
                .font(.headline)
            Picker("Destination", selection: $editor.destinationIsAbsolute) {
                Text("Inside source folder").tag(false)
                Text("Other folder").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Destination kind")
            if editor.destinationIsAbsolute {
                LabeledContent("Folder") {
                    Text(editor.absolutePath.isEmpty ? "Not chosen" : editor.absolutePath)
                        .foregroundStyle(editor.absolutePath.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                Button("Choose Folder…") { model.chooseAbsoluteDestination() }
            } else {
                TextField("Finance/Invoices", text: $editor.relativePath)
                    .accessibilityLabel("Folder inside the source folder")
            }
            if let warning = editor.destinationWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var extensions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extensions")
                .font(.headline)
            Text("Files whose extension is one of these. Extra conditions below are combined with All.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout {
                ForEach(editor.extensions, id: \.self) { value in
                    HStack(spacing: 4) {
                        Text(value)
                        Button {
                            editor.removeExtension(value)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(value)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                }
                TextField("Add extension", text: $editor.extensionDraft)
                    .frame(width: 120)
                    .onSubmit { editor.addExtension() }
                    .accessibilityLabel("Add extension")
                Button("Add") { editor.addExtension() }
                    .disabled(editor.extensionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When")
                .font(.headline)
            if editor.advanced == nil {
                Text("No extra conditions. Add one to match on the name, type, size, or date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RuleNodeEditor(node: advancedBinding, onDelete: { editor.advanced = nil })
            }
            if editor.advanced == nil || isSingleCondition {
                HStack {
                    Button("Add Condition") { editor.addCondition() }
                    Button("Add Group") { editor.addGroup() }
                }
            }
            if let reason = editor.saveBlockedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(reason)
            }
        }
    }

    private var behavior: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("If a file already exists")
                .font(.headline)
            Picker("If a file already exists", selection: conflictBinding) {
                Text("Use app default").tag("default")
                Text("Ask").tag(ConflictPolicy.ask.rawValue)
                Text("Auto Rename").tag(ConflictPolicy.autoRename.rawValue)
                Text("Skip").tag(ConflictPolicy.skip.rawValue)
                Text("Replace").tag(ConflictPolicy.replace.rawValue)
            }
            .labelsHidden()
            .accessibilityLabel("Conflict behavior")
        }
    }

    private var isSingleCondition: Bool {
        if case .condition = editor.advanced { return true }
        return false
    }

    private var advancedBinding: Binding<RuleNode> {
        Binding(
            get: { editor.advanced ?? .group(.and, []) },
            set: { editor.advanced = $0 }
        )
    }

    private var conflictBinding: Binding<String> {
        Binding(
            get: { editor.conflictPolicy?.rawValue ?? "default" },
            set: { editor.conflictPolicy = ConflictPolicy(rawValue: $0) }
        )
    }
}
