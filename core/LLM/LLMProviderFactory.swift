import Foundation

/// Builds an LLMProvider from the current SettingsStore values.
/// Mirrors makeExtractorFromSettings() / makeScorerFromSettings() in server/extract.js.
public enum LLMProviderFactory {
    /// Returns the appropriate provider for the given settings.
    /// API keys are read from the Keychain via SettingsStore.
    ///
    /// Model contract: the factory configures the *default* model stored on the provider,
    /// but `ChatRequest.model` is the authoritative model sent to the API. Callers build
    /// `ChatRequest` with `settings.llmModel` (see ExtractionEngine.extract) so providers
    /// always send exactly what is in the request, not the provider's stored model field.
    /// Main-actor isolated because it reads a `SettingsStore`, which is (TASK-692). The queue never
    /// calls this directly — it goes through the `providerFactory` closure in `QueueActor`, which
    /// hops for it.
    @MainActor
    public static func makeProvider(settings: SettingsStore, session: URLSession = .shared) -> any LLMProvider {
        let provider = settings.llmProvider
        let model = settings.llmModel
        let timeout = settings.llmTimeout
        let apiKey = settings.apiKey(forProvider: provider)

        switch provider {
        case "openai":
            return OpenAIProvider(apiKey: apiKey, model: model, timeoutSeconds: timeout, session: session)
        case "anthropic":
            return AnthropicProvider(apiKey: apiKey, model: model, timeoutSeconds: timeout, session: session)
        case "google":
            return GoogleProvider(apiKey: apiKey, model: model, timeoutSeconds: timeout, session: session)
        case "openrouter":
            // TASK-462: share the rotation pool (cache + index) across the per-drain provider
            // rebuilds; nil disables rotation (single configured model).
            let pool = settings.llmOpenRouterFreeRotate ? OpenRouterModelPool.shared : nil
            return OpenRouterProvider(
                apiKey: apiKey, model: model, timeoutSeconds: timeout, session: session, pool: pool
            )
        case "deepseek":
            // DeepSeek serves an OpenAI-compatible API, so the existing transport covers it —
            // this is metadata and a picker entry, not a new client.
            return CustomProvider(
                baseURL: resolveBaseURL(provider: "deepseek", customBaseURL: ""),
                apiKey: apiKey,
                model: model,
                timeoutSeconds: timeout,
                session: session
            )
        case "custom":
            let baseURL = settings.llmBaseURL
            return CustomProvider(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                timeoutSeconds: timeout,
                session: session
            )
        default:
            // Default: LM Studio (local OpenAI-compatible)
            let baseURL = settings.llmBaseURL
            return LMStudioProvider(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                timeoutSeconds: timeout,
                session: session
            )
        }
    }

    /// Whether the named provider requires an API key to work (TASK-483). The hosted providers do;
    /// local ones (LM Studio default) and `custom` (often a local/self-hosted endpoint) don't, so we
    /// don't flag those as "unconfigured" just for lacking a key — their reachability is only knowable
    /// by trying, and the existing auto-pause-on-failure covers an unreachable local server.
    public static func requiresAPIKey(provider: String) -> Bool {
        switch provider {
        case "openai", "anthropic", "google", "openrouter", "deepseek": true
        default: false
        }
    }

    /// Base-URL-aware key requirement: a `custom` provider needs a key only when it's a REMOTE
    /// endpoint (a loopback / on-device URL like LM Studio doesn't). One policy shared by the AI form
    /// (`AIProviderFormModel.needsAPIKey`) and the readiness gate (`AIReadiness`) so they can't drift
    /// (TASK-568).
    public static func requiresAPIKey(provider: String, baseURL: String) -> Bool {
        if provider == "custom" { return !ConsentHelper.isLoopbackURL(baseURL) }
        return requiresAPIKey(provider: provider)
    }

    /// Resolves the effective base URL for a given provider name.
    /// Mirrors resolveProviderBaseUrl() from server/extract.js.
    public static func resolveBaseURL(provider: String, customBaseURL: String) -> String {
        switch provider {
        case "openai": return "https://api.openai.com"
        case "openrouter": return "https://openrouter.ai/api"
        case "deepseek": return "https://api.deepseek.com"
        case "anthropic": return "https://api.anthropic.com"
        case "google": return "https://generativelanguage.googleapis.com"
        default:
            let base = customBaseURL.isEmpty ? "http://127.0.0.1:1234" : customBaseURL
            return base.hasSuffix("/") ? String(base.dropLast()) : base
        }
    }
}
