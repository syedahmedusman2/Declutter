import SwiftUI

struct ScanView: View {
    @Bindable var model: ScanViewModel
    var onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
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
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.gradient)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.folderPath ?? "No folder selected")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await model.chooseFolderAndScan() }
            } label: {
                Label("Choose Folder", systemImage: "folder.badge.gearshape")
            }
            .buttonStyle(.bordered)
            .disabled(model.isScanning)

            Button {
                Task { await model.rescan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.folderPath == nil || model.isScanning)

            Button {
                onPreview()
            } label: {
                Label("Preview Plan", systemImage: "checklist")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.folderPath == nil || model.isScanning || model.rows.isEmpty)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.needsReauthorization {
            PermissionLostView(message: model.errorText ?? "Access to the folder was revoked. Choose the folder again.") {
                Task { await model.chooseFolderAndScan() }
            }
        } else if model.isScanning {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Scanning folder...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.rows.isEmpty {
            ContentUnavailableView(
                model.folderPath == nil ? "Choose a Folder" : "Folder Clean",
                systemImage: model.folderPath == nil ? "folder.badge.questionmark" : "sparkles",
                description: Text(
                    model.folderPath == nil
                        ? "Select a folder like Downloads or Desktop to see matching categories."
                        : "No unorganized files found matching current active rules."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(model.rows) {
                TableColumn("File") { row in
                    HStack(spacing: 8) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(row.name)
                            .lineLimit(1)
                    }
                }
                TableColumn("Category") { row in
                    Text(row.categoryName)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                }
                TableColumn("Destination") { row in
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(row.destinationPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var statusLine: String {
        if model.isScanning { return "Scanning…" }
        if model.folderPath == nil { return "Pick a folder to see each file’s category." }
        return "\(model.rows.count) files ready to organize"
    }
}
