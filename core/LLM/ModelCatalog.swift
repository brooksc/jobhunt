import Foundation

/// Fetches the list of available models from a provider's own API, so the app never has to
/// hardcode model identifiers. Every HTTP provider exposes a list endpoint:
///   - OpenAI-compatible (LM Studio, Custom, OpenRouter, OpenAI): `GET {base}/v1/models` → `{data:[{id}]}`
///   - Anthropic: `GET /v1/models` (x-api-key + anthropic-version) → `{data:[{id}]}`
///   - Google: `GET /v1beta/models` (x-goog-api-key) → `{models:[{name, supportedGenerationMethods}]}`
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
            // Diagnostic logging for "valid key still fails" reports (TASK-489). Logs the request and a
            // SAFE key fingerprint (length + first/last 4 + whitespace/ASCII flags) — never the full
            // secret — plus the server's reason. View in Console.app, filter process "Jobhunt".
            let authHeader = headers["x-goog-api-key"] ?? headers["Authorization"] ?? headers["x-api-key"] ?? ""
            let rawKey = authHeader.hasPrefix("Bearer ") ? String(authHeader.dropFirst(7)) : authHeader
            NSLog("[jobhunt-llm] model fetch FAILED status=%d url=%@ key=%@ body=%@",
                  http.statusCode, url.absoluteString, Self.keyFingerprint(rawKey),
                  String(data: data.prefix(500), encoding: .utf8) ?? "<non-utf8>")
            throw ModelCatalogError.httpError(statusCode: http.statusCode, serverMessage: Self.serverErrorMessage(data))
        }
        return data
    }

    /// A non-secret fingerprint of an API key for diagnostics: length, first/last 4 chars, and whether
    /// it carries whitespace or non-ASCII bytes (the usual cause of a "valid key rejected" mystery).
    static func keyFingerprint(_ key: String) -> String {
        if key.isEmpty { return "EMPTY" }
        let head = String(key.prefix(4))
        let tail = String(key.suffix(4))
        let hasWhitespace = key.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        let isASCII = key.allSatisfy { $0.isASCII }
        return "len=\(key.count) \(head)…\(tail) ws=\(hasWhitespace) ascii=\(isASCII)"
    }

    /// Pull the human-readable reason out of a provider error body. Google, OpenAI, and Anthropic all
    /// return `{ "error": { "message": ... } }`, so the same parse surfaces the real cause (e.g. a
    /// restricted key or a disabled API) instead of a bare status code.
    private static func serverErrorMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = obj["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let message = obj["error"] as? String, !message.isEmpty { return message }
        return nil
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
    case httpError(statusCode: Int, serverMessage: String? = nil)
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            return "Enter an API key to load \(provider) models"
        case .missingBaseURL:
            return "Enter a base URL to load models"
        case let .httpError(code, serverMessage):
            var text = "Could not load models (HTTP \(code))"
            // 401/403 = the key reached the provider but was rejected/forbidden — almost always a
            // restricted key or a not-enabled API, NOT a malformed key (that returns 400). Point the
            // user at the real fix rather than leaving them staring at a status code.
            if code == 401 || code == 403 {
                text += ": the API key was rejected. Make sure it's an unrestricted key (no HTTP-referrer / "
                    + "IP / app restrictions) and that the provider's API is enabled for it."
            }
            if let serverMessage { text += "\n\(serverMessage)" }
            return text
        case .decodeFailed:
            return "Could not read the model list from the provider"
        }
    }
}
