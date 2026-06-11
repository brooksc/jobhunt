// swiftlint:disable nesting
import Foundation

/// Builds an LLMProvider from the current SettingsStore values.
/// Mirrors makeExtractorFromSettings() / makeScorerFromSettings() in server/extract.js.
public enum LLMProviderFactory {
    /// Returns the appropriate provider for the given settings.
    /// API keys are read from the Keychain via SettingsStore.
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
        case "foundation_models":
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

// MARK: - OpenRouter free-model rotation

/// Manages the OpenRouter free-model rotation pool.
/// Mirrors selectFreeStructuredModels() / refreshRotationPool() from server/extract.js.
public actor OpenRouterRotationPool {
    public static let shared = OpenRouterRotationPool()

    private let ttl: TimeInterval = 3600 // 1 hour
    private var modelIDs: [String] = []
    private var fetchedAt: Date = .distantPast
    private var counter: Int = 0

    private init() {}

    /// Returns the current pool (may be stale — call `refresh` to update).
    public var ids: [String] {
        modelIDs
    }

    /// Pick the next model round-robin.
    public func next() -> String? {
        guard !modelIDs.isEmpty else { return nil }
        let model = modelIDs[counter % modelIDs.count]
        counter += 1
        return model
    }

    /// Fetch and cache the free model list from OpenRouter (hourly TTL).
    public func refresh(apiKey: String, force: Bool = false, session: URLSession = .shared) async {
        guard force || Date().timeIntervalSince(fetchedAt) > ttl else { return }
        do {
            let ids = try await fetchFreeStructuredModelIDs(apiKey: apiKey, session: session)
            if !ids.isEmpty {
                modelIDs = ids
                fetchedAt = Date()
            }
        } catch {
            // Keep stale pool on error
        }
    }

    private func fetchFreeStructuredModelIDs(apiKey: String, session: URLSession) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.timeoutInterval = 6
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw LLMProviderError.noResponse
        }
        let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        return selectFreeStructuredModels(from: decoded.data ?? [])
    }

    /// Filter OpenRouter models to those that are free and support structured output.
    /// Mirrors selectFreeStructuredModels() from server/extract.js.
    private func selectFreeStructuredModels(from models: [OpenRouterModel]) -> [String] {
        models.compactMap { model -> String? in
            let isFree = (Double(model.pricing?.prompt ?? "1") ?? 1) == 0
                && (Double(model.pricing?.completion ?? "1") ?? 1) == 0
            guard isFree else { return nil }

            let supportedParams = model.supportedParameters ?? []
            let hasStructured = supportedParams.contains("structured_outputs") || supportedParams
                .contains("response_format")
            guard hasStructured else { return nil }

            // Text-only output check (exclude audio/image generation models)
            if let outputs = model.architecture?.outputModalities {
                let textOnly = outputs.contains("text") && outputs.allSatisfy { $0 == "text" }
                guard textOnly else { return nil }
            }

            return model.id
        }
    }
}

// MARK: - OpenRouter models API Codable

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]?
}

private struct OpenRouterModel: Decodable {
    let id: String
    let pricing: Pricing?
    let supportedParameters: [String]?
    let architecture: Architecture?

    enum CodingKeys: String, CodingKey {
        case id, pricing, architecture
        case supportedParameters = "supported_parameters"
    }

    struct Pricing: Decodable {
        let prompt: String?
        let completion: String?
    }

    struct Architecture: Decodable {
        let outputModalities: [String]?

        enum CodingKeys: String, CodingKey {
            case outputModalities = "output_modalities"
        }
    }
}

// swiftlint:enable nesting
