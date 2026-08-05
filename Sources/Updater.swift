import SwiftUI

// Lurent ships through the App Store, which updates it. There is no in-app updater:
// the Store forbids apps that update themselves, and Sparkle was removed with the
// Developer ID channel.
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
