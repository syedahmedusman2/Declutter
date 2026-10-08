import DeclutterCore
import SwiftUI

struct SidebarStatusCard: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay {
                        if model.monitor.status.state == .monitoring {
                            Circle()
                                .stroke(statusColor.opacity(0.4), lineWidth: 3)
                                .scaleEffect(1.4)
                        }
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(statusSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                switch model.monitor.status.state {
                case .monitoring:
                    Button {
                        model.pauseMonitoring()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        model.stopMonitoring()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                case .paused:
                    Button {
                        model.resumeMonitoring()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        model.stopMonitoring()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                case .permissionRequired:
                    Button {
                        model.reauthorize()
                    } label: {
                        Label("Authorize", systemImage: "lock.open.fill")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)

                default:
                    Button {
                        model.startMonitoring()
                    } label: {
                        Label("Start Monitoring", systemImage: "play.fill")
                            .font(.caption2.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.6))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch model.monitor.status.state {
        case .monitoring: .green
        case .paused: .orange
        case .permissionRequired: .red
        case .error: .red
        default: .secondary
        }
    }

    private var statusTitle: String {
        switch model.monitor.status.state {
        case .monitoring: "Monitoring Active"
        case .paused: "Monitoring Paused"
        case .permissionRequired: "Access Needed"
        case .error: "Monitoring Error"
        default: "Monitoring Idle"
        }
    }

    private var statusSubtitle: String {
        if let detail = model.monitor.detail {
            return detail
        }
        if model.monitor.status.state == .monitoring {
            return model.uptimeDescription
        }
        return "Automatic organization off"
    }
}
