// swiftlint:disable nesting
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
            return OpenRouterProvider(apiKey: apiKey, model: model, timeoutSeconds: timeout, session: session)
        case "foundation_models", "apple":
            // "apple" is kept as a legacy alias for settings saved before TASK-320.
            return FoundationModelsProvider()
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

    /// Resolves the effective base URL for a given provider name.
    /// Mirrors resolveProviderBaseUrl() from server/extract.js.
    public static func resolveBaseURL(provider: String, customBaseURL: String) -> String {
        switch provider {
        case "openai": return "https://api.openai.com"
        case "openrouter": return "https://openrouter.ai/api"
        case "anthropic": return "https://api.anthropic.com"
        case "google": return "https://generativelanguage.googleapis.com"
        default:
            let base = customBaseURL.isEmpty ? "http://127.0.0.1:1234" : customBaseURL
            return base.hasSuffix("/") ? String(base.dropLast()) : base
        }
    }
}

// swiftlint:enable nesting
