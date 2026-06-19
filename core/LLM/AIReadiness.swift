import Foundation

/// Single source of truth for "is the AI provider usable for extraction / fit scoring?" — used by
/// both the UI readiness banner (`AIConfig`) and the queue's provider-configured gate so the two
/// can't drift (TASK-512).
///
/// Readiness means: a model is selected, and — for key-requiring hosted providers — an API key is
/// present. Local providers (LM Studio / custom loopback) need a model but no key. Previously the
/// queue only checked the key, so a default install with an empty `llmModel` ran extraction and
/// failed with `noModelSelected` instead of surfacing the "set up an AI provider" nudge.
public enum AIReadiness {
    public static func isConfigured(
        provider: String,
        model: String,
        apiKey: @autoclosure () -> String
    ) -> Bool {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if LLMProviderFactory.requiresAPIKey(provider: provider) {
            return !apiKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    /// Convenience over a `SettingsStore` — the form both the queue wiring and the UI call. The
    /// key read is deferred (autoclosure) so local providers never touch the Keychain.
    public static func isConfigured(_ settings: SettingsStore) -> Bool {
        isConfigured(
            provider: settings.llmProvider,
            model: settings.llmModel,
            apiKey: settings.apiKey(forProvider: settings.llmProvider)
        )
    }
}
