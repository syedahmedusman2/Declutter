import SwiftUI

struct MonitorBar: View {
    var model: AppModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                StatusLabel(
                    text: model.statusLine,
                    systemImage: MonitorSymbol.image(for: model.monitor.status.state.rawValue)
                )
                .font(.subheadline.weight(.semibold))
                if let detail = model.monitor.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch model.monitor.status.state {
            case .monitoring:
                Button("Pause") { model.pauseMonitoring() }
                    .accessibilityHint("Holds new files until you resume.")
                Button("Stop") { model.stopMonitoring() }
            case .paused:
                Button("Resume") { model.resumeMonitoring() }
                Button("Stop") { model.stopMonitoring() }
            case .permissionRequired:
                Button("Reauthorize Folder") { model.reauthorize() }
                Button("Start Monitoring") { model.startMonitoring() }
            default:
                Button("Start Monitoring") { model.startMonitoring() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
