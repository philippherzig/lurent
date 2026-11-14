import SwiftUI

// There is no in-app updater: Sparkle was removed for an App Store move that was
// later dropped. Lurent is open source; new versions come from GitHub releases.
//
// These two types stay as empty seams so App.swift keeps its shape — dropping them
// would mean touching the scene for no gain, and a future updater (if the app ever
// leaves the Store) would slot straight back in here.

@MainActor
final class UpdaterViewModel: ObservableObject {}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterViewModel
    var body: some View { EmptyView() }
}
