import SwiftUI

struct ScanView: View {
    @Bindable var model: ScanViewModel
    var onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Files")
        .alert(
            "Could Not Scan Folder",
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
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.folderPath ?? "No folder selected")
                    .font(.headline)
                    .textSelection(.enabled)
                    .accessibilityLabel(model.folderPath ?? "No folder selected")
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(statusLine)
            }
            Spacer()
            Button("Preview") {
                onPreview()
            }
            .disabled(model.folderPath == nil || model.isScanning)
            Button("Choose Folder") {
                Task { await model.chooseFolderAndScan() }
            }
            .disabled(model.isScanning)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.needsReauthorization {
            PermissionLostView(message: model.errorText ?? "Access to the folder was revoked. Choose the folder again.") {
                Task { await model.chooseFolderAndScan() }
            }
        } else if model.isScanning {
            ProgressView("Scanning")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.rows.isEmpty {
            ContentUnavailableView(
                model.folderPath == nil ? "Choose a Folder" : "No Files",
                systemImage: "folder",
                description: Text(
                    model.folderPath == nil
                        ? "The chooser opens in Downloads. Files are listed with a category. Nothing is moved."
                        : "Hidden files, folders, partial downloads, and links are skipped."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(model.rows) {
                TableColumn("File", value: \.name)
                TableColumn("Category", value: \.categoryName)
                TableColumn("Destination", value: \.destinationPath)
            }
        }
    }

    private var statusLine: String {
        if model.isScanning { return "Scanning…" }
        if model.folderPath == nil { return "Pick a folder to see each file’s category." }
        return "\(model.rows.count) files"
    }
}
