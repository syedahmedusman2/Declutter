import AppKit
import DeclutterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRuntime.shared?.bootstrap()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        guard let model = AppRuntime.shared else { return true }
        return model.settings.policy.terminatesWhenLastWindowCloses
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = AppRuntime.shared else { return .terminateNow }
        let active = model.monitor.status.state == .monitoring || model.monitor.status.state == .paused
        if model.settings.policy.shouldPromptBeforeQuit(monitoringActive: active) {
            return prompt(model)
        }
        guard active else { return .terminateNow }
        Task {
            await model.monitor.stopForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func prompt(_ model: AppModel) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Monitoring will stop"
        alert.informativeText = "Monitoring will stop. Keep running in the background instead?"
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Always Quit")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.settings.setRunInBackground(true)
            return .terminateCancel
        case .alertThirdButtonReturn:
            model.settings.setAlwaysQuit(true)
            Task {
                await model.monitor.stopForQuit()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        default:
            Task {
                await model.monitor.stopForQuit()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}
