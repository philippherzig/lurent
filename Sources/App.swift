import SwiftUI

@main
struct LurentApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1200, minHeight: 680)
        }
        .defaultSize(width: 1440, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
