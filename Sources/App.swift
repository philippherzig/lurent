import AppKit
import SwiftUI

@main
struct LurentApp: App {
    static let mainWindowID = "main"

    @StateObject private var model = AppModel()
    @StateObject private var updater = UpdaterViewModel()

    init() {
        // Single-window app: window tabbing buys nothing and the system tab bar
        // stalls the UI. Turning it off here (before any window exists) also
        // strips the "Show Tab Bar" / "Merge All Windows" menu items.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        // Not a single `Window` scene: that quits the whole app when its window closes.
        WindowGroup(id: Self.mainWindowID) {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1090, minHeight: 660)
                // `.lurent` documents arriving from the Finder — double-click, drop on
                // the Dock icon, "Open With".
                //
                // Deliberately not an NSApplicationDelegateAdaptor: attaching a
                // delegate to a WindowGroup app makes it open a second, empty window
                // at launch, and `applicationShouldOpenUntitledFile` does not suppress
                // it. `onOpenURL` receives the same file URLs and costs no delegate.
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == WallpaperLibrary.packageExtension else { return }
                    model.importProject(at: url)
                }
                // Without this the existing window declines the document event and
                // SwiftUI opens a second one for it. Lurent has exactly one window and
                // the opened project lands in its rail.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        // The preview renders a square master, so the centre pane wants to be roughly
        // square too: height 840 − 2×40 padding ≈ 760 image side, + padding ≈ 840 pane
        // width, + 108 library rail + 320 inspector ≈ 1270 total. Sized so the square
        // fills the pane instead of floating in wasted horizontal space.
        .defaultSize(width: 1270, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
            // App Review (guideline 4) rejected a build where closing the window left
            // no menu item to bring it back; SwiftUI does not list it by itself.
            // After `.windowArrangement`, because `.windowList` renders nothing.
            CommandGroup(after: .windowArrangement) {
                ShowMainWindowCommand()
            }
        }

        Settings {
            APIKeysSettingsView()
        }
    }
}

private struct ShowMainWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Lurent") {
            // A WindowGroup would happily open a second window; Lurent has one.
            // A closed SwiftUI window can linger in `NSApp.windows`; only a shown or
            // minimized one counts.
            if let window = NSApp.windows.first(where: {
                $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
            }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: LurentApp.mainWindowID)
            }
        }
            .keyboardShortcut("0")
    }
}
