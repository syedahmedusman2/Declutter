import DownloadOrganizerCore
import SwiftUI

struct DashboardView: View {
    var model: AppModel
    @Bindable var activity: ActivityViewModel
    var folderPath: String?
    var needsReauthorization: Bool
    var permissionMessage: String?
    var openRules: () -> Void
    var reauthorize: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                status
                folder
                stats
                actions
                recent
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Dashboard")
        .task { await activity.reload() }
        .accessibilityElement(children: .contain)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusLabel(
                text: model.statusLine,
                systemImage: MonitorSymbol.image(for: model.monitor.status.state.rawValue)
            )
            .font(.title3)
            Text(model.uptimeDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let detail = model.monitor.detail {
                Text(detail)
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var folder: some View {
        if needsReauthorization {
            PermissionLostView(message: permissionMessage ?? "Access to the folder was revoked. Choose the folder again.", reauthorize: reauthorize)
                .frame(height: 220)
        } else {
            LabeledContent("Folder") {
                Text(folderPath ?? "No folder selected")
                    .textSelection(.enabled)
            }
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Files organized today: \(activity.stats.organizedToday)")
            Text("Total organized: \(activity.stats.totalOrganized)")
            Text("Skipped: \(activity.stats.skipped). Failed: \(activity.stats.failed).")
            if let last = activity.stats.lastOperation {
                Text("Last activity \(last.formatted(.relative(presentation: .named)))")
            } else {
                Text("Last activity: none yet")
            }
            if !activity.stats.perCategory.isEmpty {
                Text(categoryLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var categoryLine: String {
        activity.stats.perCategory.keys.sorted().map { name in
            "\(name) \(activity.stats.perCategory[name] ?? 0)"
        }.joined(separator: ", ")
    }

    private var actions: some View {
        HStack {
            Button("Organize Existing Files") { model.organizeExisting() }
                .accessibilityHint("Opens a preview. Files move only after you confirm.")
            if model.monitor.status.state == .monitoring {
                Button("Pause Monitoring") { model.pauseMonitoring() }
            } else if model.monitor.status.state == .paused {
                Button("Resume Monitoring") { model.resumeMonitoring() }
            } else {
                Button("Start Monitoring") { model.startMonitoring() }
            }
            Button("Open Rules", action: openRules)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent activity")
                .font(.headline)
            if activity.items.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "clock",
                    description: Text("Moves you confirm, and files organized while monitoring, show up here.")
                )
                .frame(maxWidth: 420)
            } else {
                ForEach(activity.items.prefix(8)) { item in
                    Text("\(item.originalName) → \(item.finalName)")
                        .accessibilityLabel("\(item.originalName) moved to \(item.finalName), \(ActivityFormatting.status(item.status))")
                }
            }
        }
    }
}
