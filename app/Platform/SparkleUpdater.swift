// Sparkle auto-update integration (DMG flavor only).
// Full Sparkle 2 integration requires adding the Sparkle SPM package to Project.swift.
// Stub for now: exposes the check-for-updates menu command hook.
import Foundation

#if !MAS_BUILD
public enum SparkleUpdater {
    public static func checkForUpdates() {
        // TODO: integrate Sparkle 2 (add to Project.swift as SPM package once cert available)
        // SPM: https://github.com/sparkle-project/Sparkle 2.x
        // Appcast URL: https://github.com/brooksc/jobhunt/releases/latest/download/appcast.xml
        NSLog("Sparkle: check for updates (stub — integrate Sparkle 2 package)")
    }
}
#endif
