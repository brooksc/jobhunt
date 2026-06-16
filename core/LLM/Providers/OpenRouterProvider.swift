import Foundation

/// OpenRouter provider — OpenAI-compatible API at openrouter.ai.
/// Concurrency limit 3. Adds OpenRouter-specific HTTP headers.
/// Mirrors postOpenAICompatibleCompletion() with openrouter base URL.
public final class OpenRouterProvider: LLMProvider, @unchecked Sendable {
    public let id = "openrouter"
    public let concurrencyLimit = 3
    /// Max distinct free models tried per request when rotating (TASK-462, Electron parity).
    static let maxRotationModels = 4

    private let apiKey: String
    private let model: String
    private let timeoutSeconds: Int
    private let session: URLSession
    /// When non-nil, rotate over free structured-output models with failover instead of `model`.
    private let pool: OpenRouterModelPool?

    public init(
        apiKey: String,
        model: String = "",
        timeoutSeconds: Int = 300,
        session: URLSession = .shared,
        pool: OpenRouterModelPool? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.session = session
        self.pool = pool
    }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        guard let pool else {
            return try await send(request) // rotation off — single configured model, unchanged
        }
        let candidates = await pool.nextModels(count: Self.maxRotationModels, apiKey: apiKey, session: session)
        guard !candidates.isEmpty else {
            return try await send(request) // pool empty (no free models / fetch failed) — fall back
        }
        // Try each candidate model in order; only throw after ALL are exhausted, so the queue sees
        // exactly one failure per fully-exhausted request and a recovered failover counts as success
        // (TASK-462 AC#4 — no premature auto-pause from per-model attempts).
        var lastError: Error?
        for modelID in candidates {
            do {
                return try await send(request.replacingModel(modelID))
            } catch {
                lastError = error
            }
        }
        throw lastError ?? LLMProviderError.noResponse
    }

    private func send(_ request: ChatRequest) async throws -> ChatResponse {
        let extraHeaders: [String: String] = [
            "HTTP-Referer": "https://github.com/jobhunt-app/jobhunt",
            "X-Title": "Jobhunt"
        ]
        return try await OpenAICompatibleTransport.complete(
            request: request,
            baseURL: "https://openrouter.ai/api",
            apiKey: apiKey,
            providerID: id,
            extraHeaders: extraHeaders,
            session: session,
            timeoutSeconds: timeoutSeconds
        )
    }
}
