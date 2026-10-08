// Links AppIntents so Xcode's metadata step does not warn on an app that has no shortcuts yet.
import AppIntents
import SwiftUI

@main
struct DeclutterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
        AppRuntime.shared = model
    }

    var body: some Scene {
        WindowGroup(id: AppWindow.organizer) {
            RootView(model: model)
                .preferredColorScheme(model.settings.colorScheme)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Category") { model.send(.newCategory) }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Rescan") { model.send(.rescan) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Execute") { model.send(.execute) }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Search") { model.send(.focusSearch) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Pause or Resume") { model.send(.togglePause) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo Last Batch") { model.send(.undoLastBatch) }
                    .keyboardShortcut("z", modifiers: .command)
            }
        }
        MenuBarExtra(
            AppBranding.name,
            systemImage: "arrow.down.circle",
            isInserted: Binding(
                get: { model.settings.menuBarVisible },
                set: { model.settings.setShowMenuBarIcon($0) }
            )
        ) {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(model: model)
        }
    }
}
