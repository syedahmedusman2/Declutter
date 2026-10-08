import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.statusLine)
                .font(.headline)
            if let detail = model.monitor.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            if model.monitor.status.state == .paused {
                Button("Resume") { model.resumeMonitoring() }
            } else if model.monitor.status.state == .monitoring {
                Button("Pause") { model.pauseMonitoring() }
            }
            if model.monitor.status.state == .monitoring || model.monitor.status.state == .paused {
                Button("Stop Monitoring") { model.stopMonitoring() }
            } else {
                Button("Start Monitoring") { model.startMonitoring() }
            }
            Button("Organize Existing") {
                openOrganizer()
                model.organizeExisting()
            }
            Button("Reauthorize Folder") {
                openOrganizer()
                model.reauthorize()
            }
            Button("Open Organizer") { openOrganizer() }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }

    private func openOrganizer() {
        openWindow(id: AppWindow.organizer)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum AppWindow {
    static let organizer = "organizer"
}
