import DeclutterCore
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
                folderCard
                metricsGrid
                recentSection
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .navigationTitle("Dashboard")
        .task { await activity.reload() }
    }

    // ── Folder & Live Monitoring Status ──────────────────────────────────────
    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if needsReauthorization {
                PermissionLostView(
                    message: permissionMessage ?? "Access to the folder was revoked. Choose the folder again.",
                    reauthorize: reauthorize
                )
                .frame(height: 180)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Folder Icon
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.gradient)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: Color.blue.opacity(0.25), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(folderName)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)

                            statusBadge
                        }

                        Text(folderPath ?? "No folder selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let detail = model.monitor.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        model.organizeExisting()
                    } label: {
                        Label("Organize Existing Files", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Scan and organize files currently sitting in this folder")

                    if model.monitor.status.state == .monitoring {
                        Button {
                            model.pauseMonitoring()
                        } label: {
                            Label("Pause Monitoring", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                    } else if model.monitor.status.state == .paused {
                        Button {
                            model.resumeMonitoring()
                        } label: {
                            Label("Resume Monitoring", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            model.startMonitoring()
                        } label: {
                            Label("Start Monitoring", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        openRules()
                    } label: {
                        Label("Configure Rules", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
        }
    }

    private var folderName: String {
        guard let path = folderPath, !path.isEmpty else { return "No Folder Selected" }
        return (path as NSString).lastPathComponent
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)

            Text(statusBadgeText)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(statusDotColor.opacity(0.12)))
        .foregroundStyle(statusDotColor)
    }

    private var statusDotColor: Color {
        switch model.monitor.status.state {
        case .monitoring: .green
        case .paused: .orange
        case .permissionRequired: .red
        case .error: .red
        default: .secondary
        }
    }

    private var statusBadgeText: String {
        switch model.monitor.status.state {
        case .monitoring: "Monitoring Active"
        case .paused: "Paused"
        case .permissionRequired: "Permission Needed"
        case .error: "Error"
        default: "Idle"
        }
    }

    // ── Metric Tiles ─────────────────────────────────────────────────────────
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            metricCard(
                title: "Organized Today",
                value: "\(activity.stats.organizedToday)",
                systemImage: "calendar.badge.checkmark",
                tint: .blue
            )
            metricCard(
                title: "Total Organized",
                value: "\(activity.stats.totalOrganized)",
                systemImage: "tray.full.fill",
                tint: .purple
            )
            metricCard(
                title: "Last Activity",
                value: lastActivityString,
                systemImage: "clock.arrow.circlepath",
                tint: .teal
            )
        }
    }

    private var lastActivityString: String {
        if let last = activity.stats.lastOperation {
            return last.formatted(.relative(presentation: .named))
        }
        return "None yet"
    }

    private func metricCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(tint)
            }

            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        }
    }

    // ── Recent Activity Feed ─────────────────────────────────────────────────
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
            }

            if activity.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No Files Organized Yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Files moved during scans or background monitoring will appear here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary.opacity(0.2))
                }
            } else {
                VStack(spacing: 1) {
                    ForEach(activity.items.prefix(6)) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "doc")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)

                            Text(item.originalName)
                                .font(.body)
                                .lineLimit(1)

                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            Text(item.destinationPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Text(item.createdAt.formatted(.relative(presentation: .named)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.quaternary.opacity(0.3))

                        if item.id != activity.items.prefix(6).last?.id {
                            Divider()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
                }
            }
        }
    }
}
