import Foundation

/// Localhost / on-device providers are always consented — no data leaves the device.
/// Cloud providers require explicit user opt-in (App Store 5.1.2(i)).
public enum ConsentHelper {
    private static let alwaysLocalProviders: Set<String> = ["lmstudio", "foundation_models"]

    /// Returns true when the provider may receive job/resume data without explicit consent.
    ///
    /// - `lmstudio` and `foundation_models` are always local.
    /// - `custom` is local only when the configured base URL resolves to a loopback address.
    ///   A remote custom URL is treated as a cloud provider and requires explicit consent.
    /// - All other providers (openai, anthropic, google, openrouter) require explicit consent.
    public static func isConsented(provider: String, settings: SettingsStore) -> Bool {
        if alwaysLocalProviders.contains(provider) { return true }
        if provider == "custom" {
            return isLoopbackURL(settings.llmBaseURL)
        }
        let key = "llm_consent_\(provider)"
        return settings.string(forKey: key) == "1"
    }

    /// Evaluate consent from pre-captured snapshot values (safe for use in background actors).
    public static func isConsented(provider: String, baseURL: String, consentGranted: Bool) -> Bool {
        if alwaysLocalProviders.contains(provider) { return true }
        if provider == "custom" {
            if isLoopbackURL(baseURL) { return true }
            return consentGranted
        }
        return consentGranted
    }

    public static func setConsent(provider: String, granted: Bool, settings: SettingsStore) {
        let key = "llm_consent_\(provider)"
        settings.set(granted ? "1" : "0", forKey: key)
    }

    /// True when the URL resolves to a loopback / on-device address.
    ///
    /// Uses URLComponents host parsing to avoid substring-match bypasses (e.g. "notlocalhost.evil.com").
    /// Accepted: localhost, 127.x.x.x, ::1. Rejected: 0.0.0.0 and anything else.
    public static func isLoopbackURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url),
              let host = components.host else { return false }
        let h = host.lowercased()
        // URLComponents preserves brackets for IPv6 literals (e.g. "[::1]")
        if h == "localhost" || h == "::1" || h == "[::1]" { return true }
        let parts = h.split(separator: ".").map(String.init)
        if parts.count == 4, parts[0] == "127", parts.allSatisfy({ Int($0) != nil }) { return true }
        return false
    }
}
