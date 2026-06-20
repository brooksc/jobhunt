// Auto-update for Developer ID (DMG) builds via Sparkle 2.
//
// MAS builds exclude Sparkle entirely: the App Store provides updates and bundling a third-party
// updater violates App Review. This whole file is compiled out under MAS_BUILD, and
// `release-mas.yml` generates the project with TUIST_MAS_ONLY=1 so Sparkle is never even linked
// into the MAS binary (see Project.swift / TASK-566).
//
// The appcast (SUFeedURL) and EdDSA public key (SUPublicEDKey) live in the DMG Info.plist, set by
// Project.swift. `release-dmg.yml` EdDSA-signs each DMG with the matching private key and publishes
// appcast.xml as a release asset, so a tampered DMG is rejected.
#if !MAS_BUILD
    import Combine
    import Sparkle
    import SwiftUI

    /// Owns the Sparkle updater for the app's lifetime. Created once in `JobhuntApp.init`.
    @MainActor
    final class SparkleUpdaterController: ObservableObject {
        private let controller: SPUStandardUpdaterController

        /// Mirrors `SPUUpdater.canCheckForUpdates` so the menu item disables while a check runs.
        @Published private(set) var canCheckForUpdates = false

        init() {
            // startingUpdater: true begins scheduled background checks against SUFeedURL.
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            controller.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
        }

        func checkForUpdates() {
            controller.updater.checkForUpdates()
        }
    }

    /// "Check for Updates…" menu command, disabled while a check is already in flight.
    struct CheckForUpdatesCommand: View {
        @ObservedObject var updater: SparkleUpdaterController

        var body: some View {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
#endif
