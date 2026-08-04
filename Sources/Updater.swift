import SwiftUI

// The App Store forbids apps that update themselves, so the Store variant is built
// with `-D APP_STORE` and ships without Sparkle at all — neither the framework nor
// the code below. The Developer ID build is unaffected and keeps auto-updates.

#if APP_STORE

/// Stand-in for the Sparkle-backed updater. Updates arrive through the App Store in
/// this build, so there is nothing to drive.
@MainActor
final class UpdaterViewModel: ObservableObject {}

/// Renders nothing: a Store build has no "check for updates" item in its app menu.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterViewModel
    var body: some View { EmptyView() }
}

#else

import Sparkle

/// Thin SwiftUI-facing wrapper around Sparkle's standard updater. The updater
/// starts itself on launch and reads `SUFeedURL` + `SUPublicEDKey` from the
/// Info.plist; automatic background checks are governed by `SUEnableAutomaticChecks`.
@MainActor
final class UpdaterViewModel: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors `SPUUpdater.canCheckForUpdates` to drive the menu item's enabled
    /// state — Sparkle sets it false when it currently can't begin a check.
    @Published var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manual "check now" — shows Sparkle's UI (progress, release notes, install).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

/// The "Nach Updates suchen…" item for the app menu.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Button("Nach Updates suchen…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
    }
}

#endif
