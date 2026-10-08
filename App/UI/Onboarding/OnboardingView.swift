import DeclutterCore
import SwiftUI

struct OnboardingView: View {
    var model: AppModel
    @Bindable var scan: ScanViewModel
    @Bindable var preview: PreviewViewModel
    var library: CategoryLibrary
    var onFinish: (_ organize: Bool) -> Void

    @State private var step = 0
    @State private var confirmMove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step \(step + 1) of 6")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Step \(step + 1) of 6")
            content
            Spacer(minLength: 0)
            buttons
        }
        .padding(24)
        .frame(width: 560, height: 460)
        .interactiveDismissDisabled(step < 2)
        .confirmationDialog(
            "Move these files?",
            isPresented: $confirmMove,
            titleVisibility: .visible
        ) {
            Button("Move Files") { onFinish(true) }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("This is the confirmation. Nothing has been moved yet.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            Text("Welcome to \(AppBranding.name)")
                .font(.title2)
            Text("This app sorts a folder you choose. It previews every move, and it does not move anything until you confirm.")
        case 1:
            Text("Choose a folder")
                .font(.title2)
            Text("Downloads is the suggested folder. The chooser opens there. The app only reads files you allow.")
            if let path = scan.folderPath {
                Label(path, systemImage: "folder")
                    .accessibilityLabel("Selected folder \(path)")
            } else {
                Text("No folder selected yet.")
            }
            Button("Choose Folder") {
                Task { await scan.chooseFolderAndScan() }
            }
            .accessibilityHint("Opens the folder panel, starting in Downloads.")
        case 2:
            Text("Folder access")
                .font(.title2)
            Text("macOS keeps the folder private until you pick it. The app stores a bookmark so it can keep organizing after you quit. If you later revoke access, use Reauthorize Folder. No files are moved in this step.")
        case 3:
            Text("How should new files be handled?")
                .font(.title2)
            Picker("Watch", selection: Binding(
                get: { model.settings.automationMode },
                set: { model.settings.setAutomationMode($0) }
            )) {
                Text("Existing files only").tag(AutomationMode.existingOnly)
                Text("New files only").tag(AutomationMode.newOnly)
                Text("Existing and new").tag(AutomationMode.existingAndNew)
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("Automation mode")
            Toggle("Keep organizing when the window is closed", isOn: Binding(
                get: { model.settings.runInBackground },
                set: { model.settings.setRunInBackground($0) }
            ))
            Toggle("Launch at Login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.settings.setLaunchAtLogin($0) }
            ))
            .disabled(!model.settings.runInBackground)
            if !model.settings.runInBackground {
                Text("Turn on background running before launching at login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case 4:
            Text("Default categories")
                .font(.title2)
            Text("These categories are editable later. Nothing is moved while you review them.")
            List(reviewCategories) { category in
                HStack {
                    Image(systemName: category.iconSymbol)
                        .accessibilityHidden(true)
                    Text(category.name)
                    Spacer()
                    Text(category.destination.path)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        default:
            Text("Preview")
                .font(.title2)
            Text("This is a dry run. Files stay where they are until you confirm on this step.")
            if preview.isPlanning {
                ProgressView("Preparing preview")
            } else if preview.filteredRows.isEmpty {
                Text(scan.folderPath == nil ? "Choose a folder first." : "No files to organize.")
            } else {
                List(preview.filteredRows.prefix(12)) { row in
                    Text("\(row.fileName) → \(row.destination)")
                        .accessibilityLabel("\(row.fileName) would move to \(row.destination)")
                }
                Text("\(preview.filteredRows.count) files in the preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewCategories: [OrganizerCategory] {
        library.categories.isEmpty ? DefaultCategories.make() : library.categories
    }

    private var buttons: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            if step >= 2 {
                Button("Skip") { onFinish(false) }
                    .accessibilityHint("Finishes setup and does not move any files.")
            }
            if step == 5 {
                Button("Move These Files") { confirmMove = true }
                    .disabled(preview.filteredRows.isEmpty || preview.isPlanning)
                    .accessibilityHint("Asks you to confirm, then moves the files in the preview.")
            }
            Button(primaryTitle) { advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && scan.folderPath == nil)
        }
    }

    private var primaryTitle: String {
        switch step {
        case 5: "Finish Without Moving"
        default: "Next"
        }
    }

    private func advance() {
        if step == 4 {
            step = 5
            Task { await preview.refresh() }
            return
        }
        if step >= 5 {
            onFinish(false)
            return
        }
        step += 1
    }
}
