import SwiftUI

@main
struct LurentApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 660)
        }
        .defaultSize(width: 1440, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
