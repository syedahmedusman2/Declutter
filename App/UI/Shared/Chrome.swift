import SwiftUI

struct ReduceMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}

extension View {
    func respectReduceMotion() -> some View {
        modifier(ReduceMotion())
    }
}

struct PermissionLostView: View {
    var message: String
    var reauthorize: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Folder access is needed", systemImage: "folder.badge.questionmark")
        } description: {
            Text(message)
        } actions: {
            Button("Reauthorize Folder", action: reauthorize)
                .accessibilityLabel("Reauthorize Folder")
                .accessibilityHint("Opens the folder chooser so the app can read the folder again.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

struct StatusLabel: View {
    var text: String
    var systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .accessibilityLabel("Status: \(text)")
    }
}

enum MonitorSymbol {
    static func image(for state: String) -> String {
        switch state {
        case "monitoring": "play.circle"
        case "paused": "pause.circle"
        case "permissionRequired": "folder.badge.questionmark"
        case "error": "exclamationmark.triangle"
        default: "stop.circle"
        }
    }
}
