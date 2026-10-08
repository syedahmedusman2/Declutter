import DeclutterCore
import SwiftUI

struct PreviewView: View {
    @Bindable var model: PreviewViewModel
    var searchFocus: Int = 0
    var reauthorize: () -> Void = {}
    @State private var sortOrder = [KeyPathComparator(\PreviewRow.fileName)]
    @FocusState private var searchFocused: Bool

    private var visibleRows: [PreviewRow] {
        model.filteredRows.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            filters
            if let summary = model.summary {
                results(summary)
            }
            if model.planIsStale {
                Text("Files may have moved. Refresh the preview to see the current plan.")
                    .foregroundStyle(.orange)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Preview")
        .onChange(of: searchFocus) { _, _ in
            searchFocused = true
        }
        .alert(
            "Could Not Preview",
            isPresented: Binding(
                get: { model.errorText != nil && !model.needsReauthorization },
                set: { isPresented in
                    if !isPresented { model.errorText = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorText ?? "")
        }
        .confirmationDialog(
            "Organize these files?",
            isPresented: $model.showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Execute") {
                Task { await model.performExecute() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.confirmDetail)
        }
        .sheet(isPresented: Binding(get: { model.isExecuting }, set: { _ in })) {
            progressSheet
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.folderPath ?? "No folder selected")
                    .font(.headline)
                    .textSelection(.enabled)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Select All") { model.selectAll() }
                .disabled(visibleRows.isEmpty || model.isPlanning)
            Button("Select None") { model.selectNone() }
                .disabled(model.selection.isEmpty || model.isPlanning)
            Button("Refresh") {
                Task { await model.refresh() }
            }
            .disabled(model.isPlanning || model.isExecuting)
            Button("Execute") { model.requestExecute() }
                .disabled(!model.canExecute)
                .accessibilityHint("Keyboard shortcut Command Return. Asks before moving when the batch is large or a file would be replaced.")
        }
    }

    private var filters: some View {
        HStack {
            TextField("Search", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel("Search preview")
            Picker("Category", selection: $model.categoryFilter) {
                Text("All categories").tag("")
                ForEach(model.categoryNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(maxWidth: 220)
            Picker("Conflict", selection: $model.conflictFilter) {
                Text("All conflicts").tag(ConflictStatus?.none)
                ForEach(ConflictStatus.allCases, id: \.self) { status in
                    Text(PreviewViewModel.conflictLabel(status)).tag(Optional(status))
                }
            }
            .frame(maxWidth: 220)
        }
    }

    private func results(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary)
                .font(.headline)
            ForEach(model.problems) { problem in
                Label(
                    "\(problem.isFailure ? "Failed" : "Skipped"). \(problem.name): \(problem.message)",
                    systemImage: problem.isFailure ? "xmark.circle" : "minus.circle"
                )
                .font(.subheadline)
                .accessibilityLabel("\(problem.isFailure ? "Failed" : "Skipped"). \(problem.name): \(problem.message)")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.needsReauthorization {
            PermissionLostView(
                message: model.errorText ?? "Access to the folder was revoked. Choose the folder again."
            ) {
                reauthorize()
            }
        } else if model.isPlanning {
            ProgressView("Preparing preview")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleRows.isEmpty {
            ContentUnavailableView(
                model.folderPath == nil ? "Choose a Folder" : "Nothing to Preview",
                systemImage: "checklist",
                description: Text(emptyDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(visibleRows, selection: $model.selection, sortOrder: $sortOrder) {
                TableColumn("File", value: \.fileName)
                TableColumn("Current Location", value: \.currentLocation)
                TableColumn("Category", value: \.categoryName)
                TableColumn("Destination", value: \.destination)
                TableColumn("Rule", value: \.rule)
                TableColumn("Action", value: \.action)
                TableColumn("Conflict Status", value: \.conflict)
            }
            .contextMenu(forSelectionType: PreviewRow.ID.self) { ids in
                if !ids.isEmpty {
                    Button("Ask") { Task { await model.apply(.ask, to: ids) } }
                    Button("Auto Rename") { Task { await model.apply(.autoRename, to: ids) } }
                    Button("Skip") { Task { await model.apply(.skip, to: ids) } }
                    Button("Replace") { Task { await model.apply(.replace, to: ids) } }
                }
            }
        }
    }

    private var progressSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Organizing")
                .font(.headline)
            ProgressView(value: model.progressFraction) {
                Text(model.progressText)
            } currentValueLabel: {
                Text(model.progressCount)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelExecute() }
            }
        }
        .padding(20)
        .frame(width: 380)
        .interactiveDismissDisabled()
    }

    private var emptyDescription: String {
        if model.folderPath == nil {
            return "Choose a folder on the Files screen. The preview lists each move and does not change any files."
        }
        if model.hasMoves {
            return "No files match this search or filter."
        }
        return "This folder has no files to organize."
    }

    private var statusLine: String {
        if model.isPlanning { return "Preparing a dry run. No files are moved." }
        if model.folderPath == nil { return "Choose a folder on the Files screen." }
        return "\(model.filteredRows.count) shown. \(model.selection.count) selected."
    }
}
