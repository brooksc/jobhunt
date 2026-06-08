import Foundation

/// Localhost / on-device providers are always consented — no data leaves the device.
/// Cloud providers require explicit user opt-in (App Store 5.1.2(i)).
public enum ConsentHelper {
    private static let localhostProviders: Set<String> = ["lmstudio", "foundation_models", "custom"]

    public static func isConsented(provider: String, settings: SettingsStore) -> Bool {
        if localhostProviders.contains(provider) { return true }
        let key = "llm_consent_\(provider)"
        return settings.string(forKey: key) == "1"
    }

    public static func setConsent(provider: String, granted: Bool, settings: SettingsStore) {
        let key = "llm_consent_\(provider)"
        settings.set(granted ? "1" : "0", forKey: key)
    }
}
