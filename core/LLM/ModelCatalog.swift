import Foundation

/// Fetches the list of available models from a provider's own API, so the app never has to
/// hardcode model identifiers. Every HTTP provider exposes a list endpoint:
///   - OpenAI-compatible (LM Studio, Custom, OpenRouter, OpenAI): `GET {base}/v1/models` → `{data:[{id}]}`
///   - Anthropic: `GET /v1/models` (x-api-key + anthropic-version) → `{data:[{id}]}`
///   - Google: `GET /v1beta/models` (x-goog-api-key) → `{models:[{name, supportedGenerationMethods}]}`
/// Apple Foundation Models is a single on-device model with no list endpoint, so it returns [].
public enum ModelCatalog {
    public static func listModels(
        provider: String,
        baseURL: String,
        apiKey: String,
        session: URLSession = .shared,
        timeoutSeconds: Double = 8
    ) async throws -> [String] {
        switch provider {
        case "anthropic":
            try requireKey(apiKey, provider: provider)
            return try await fetchOpenAIStyle(
                url: "https://api.anthropic.com/v1/models?limit=1000",
                headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"],
                session: session, timeout: timeoutSeconds
            )
        case "openai":
            try requireKey(apiKey, provider: provider)
            return try await fetchOpenAIStyle(
                url: "https://api.openai.com/v1/models",
                headers: bearer(apiKey), session: session, timeout: timeoutSeconds
            )
        case "openrouter":
            // OpenRouter's model list is public — the key is optional.
            return try await fetchOpenAIStyle(
                url: "https://openrouter.ai/api/v1/models",
                headers: bearer(apiKey), session: session, timeout: timeoutSeconds
            )
        case "google":
            return try await fetchGoogle(apiKey: apiKey, session: session, timeout: timeoutSeconds)
        case "foundation_models", "apple":
            // Single on-device model — there is nothing to list or choose.
            return []
        default:
            // LM Studio, Custom, and any other OpenAI-compatible local endpoint.
            let base = normalizedBase(baseURL)
            guard !base.isEmpty else { throw ModelCatalogError.missingBaseURL }
            return try await fetchOpenAIStyle(
                url: "\(base)/v1/models",
                headers: bearer(apiKey), session: session, timeout: timeoutSeconds
            )
        }
    }

    // MARK: - Private

    private static func requireKey(_ apiKey: String, provider: String) throws {
        if apiKey.isEmpty { throw ModelCatalogError.missingAPIKey(provider: provider) }
    }

    private static func bearer(_ apiKey: String) -> [String: String] {
        apiKey.isEmpty ? [:] : ["Authorization": "Bearer \(apiKey)"]
    }

    private static func normalizedBase(_ baseURL: String) -> String {
        baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    /// Fetches an OpenAI-style `{ "data": [ { "id": ... } ] }` model list.
    private static func fetchOpenAIStyle(
        url: String,
        headers: [String: String],
        session: URLSession,
        timeout: Double
    ) async throws -> [String] {
        guard let endpoint = URL(string: url) else { throw ModelCatalogError.missingBaseURL }
        let data = try await get(endpoint, headers: headers, session: session, timeout: timeout)
        guard let decoded = try? JSONDecoder().decode(OpenAIModelList.self, from: data) else {
            throw ModelCatalogError.decodeFailed
        }
        return decoded.data.map(\.id).filter { !$0.isEmpty }.sorted()
    }

    private static func fetchGoogle(
        apiKey: String,
        session: URLSession,
        timeout: Double
    ) async throws -> [String] {
        guard !apiKey.isEmpty else { throw ModelCatalogError.missingAPIKey(provider: "google") }
        guard let endpoint = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000"
        ) else { throw ModelCatalogError.missingBaseURL }
        let data = try await get(
            endpoint, headers: ["x-goog-api-key": apiKey], session: session, timeout: timeout
        )
        guard let decoded = try? JSONDecoder().decode(GoogleModelList.self, from: data) else {
            throw ModelCatalogError.decodeFailed
        }
        return decoded.models
            .filter { ($0.supportedGenerationMethods ?? []).contains("generateContent") }
            .map { $0.name.hasPrefix("models/") ? String($0.name.dropFirst("models/".count)) : $0.name }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private static func get(
        _ url: URL,
        headers: [String: String],
        session: URLSession,
        timeout: Double
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ModelCatalogError.decodeFailed }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ModelCatalogError.httpError(statusCode: http.statusCode)
        }
        return data
    }
}

// MARK: - Response models

private struct OpenAIModelList: Decodable {
    let data: [Entry]
    struct Entry: Decodable { let id: String }
}

private struct GoogleModelList: Decodable {
    let models: [Entry]
    struct Entry: Decodable {
        let name: String
        let supportedGenerationMethods: [String]?
    }
}

// MARK: - Error

public enum ModelCatalogError: Error, LocalizedError, Equatable {
    case missingAPIKey(provider: String)
    case missingBaseURL
    case httpError(statusCode: Int)
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            "Enter an API key to load \(provider) models"
        case .missingBaseURL:
            "Enter a base URL to load models"
        case let .httpError(code):
            "Could not load models (HTTP \(code))"
        case .decodeFailed:
            "Could not read the model list from the provider"
        }
    }
}
