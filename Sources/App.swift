import AppKit
import SwiftUI

@main
struct LurentApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = UpdaterViewModel()

    init() {
        // Single-window app: window tabbing buys nothing and the system tab bar
        // stalls the UI. Turning it off here (before any window exists) also
        // strips the "Show Tab Bar" / "Merge All Windows" menu items.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 660)
        }
        // The preview now renders a square master, so the left pane wants to be
        // roughly square too: height 840 − 2×40 padding ≈ 760 image side, + padding
        // ≈ 840 pane width, + 1 divider + 320 inspector ≈ 1160 total. Sized so the
        // square fills the pane instead of floating in wasted horizontal space.
        .defaultSize(width: 1160, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
        }
    }
}
