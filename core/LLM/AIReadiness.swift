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
    /// Full readiness: a model is selected, any required API key is present (base-URL-aware so a
    /// remote `custom` endpoint needs one), AND cloud consent has been granted (TASK-567/568).
    /// `consented` is passed in already-resolved (local providers are always consented). This is the
    /// single "can we send job/resume data now?" rule — used by the UI status and the queue gate, so
    /// a cloud provider missing consent reads as not-configured (work stays queued) instead of
    /// starting and failing with ConsentError.
    public static func isConfigured(
        provider: String,
        model: String,
        apiKey: @autoclosure () -> String,
        baseURL: String,
        consented: Bool
    ) -> Bool {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if LLMProviderFactory.requiresAPIKey(provider: provider, baseURL: baseURL),
           apiKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return consented
    }

    /// Back-compat overload (model + key only) for callers/tests that don't model base URL or
    /// consent — equivalent to a loopback, already-consented context.
    public static func isConfigured(
        provider: String,
        model: String,
        apiKey: @autoclosure () -> String
    ) -> Bool {
        isConfigured(provider: provider, model: model, apiKey: apiKey(), baseURL: "", consented: true)
    }

    /// Convenience over a `SettingsStore` — the form both the queue wiring and the UI call. The
    /// key read is deferred (autoclosure) so local providers never touch the Keychain.
    @MainActor
    public static func isConfigured(_ settings: SettingsStore) -> Bool {
        isConfigured(
            provider: settings.llmProvider,
            model: settings.llmModel,
            apiKey: settings.apiKey(forProvider: settings.llmProvider),
            baseURL: settings.llmBaseURL,
            consented: ConsentHelper.isConsented(provider: settings.llmProvider, settings: settings)
        )
    }
}
