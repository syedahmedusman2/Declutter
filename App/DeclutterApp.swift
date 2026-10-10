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
        }
        .commands {
            OrganizerCommands(model: model)
        }

        MenuBarExtra(
            AppBranding.name,
            systemImage: "arrow.down.circle",
            isInserted: menuBarInserted
        ) {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private var menuBarInserted: Binding<Bool> {
        // While background mode is on, the icon cannot be removed. A constant binding
        // prevents MenuBarExtra from writing isInserted during scene updates.
        if model.settings.runInBackground {
            return .constant(true)
        }
        return Binding(
            get: { model.settings.showMenuBarIcon },
            set: { model.settings.setShowMenuBarIcon($0) }
        )
    }
}

private struct OrganizerCommands: Commands {
    var model: AppModel

    var body: some Commands {
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
}
