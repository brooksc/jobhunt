// Auto-update for DMG builds.
// Opens the GitHub Releases page so users can manually download the latest version.
// Wire full Sparkle 2 integration when a Developer ID cert is available:
//   SPM: https://github.com/sparkle-project/Sparkle 2.x
//   Appcast URL: https://github.com/brooksc/jobhunt/releases/latest/download/appcast.xml
import AppKit
import Foundation

#if !MAS_BUILD
    public enum SparkleUpdater {
        private static let releasesURL = URL(string: "https://github.com/brooksc/jobhunt/releases/latest")!

        public static func checkForUpdates() {
            NSWorkspace.shared.open(releasesURL)
        }
    }
#endif
