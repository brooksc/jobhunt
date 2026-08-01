import Foundation

/// OpenRouter provider — OpenAI-compatible API at openrouter.ai.
/// Concurrency limit 3. Adds OpenRouter-specific HTTP headers.
/// Mirrors postOpenAICompatibleCompletion() with openrouter base URL.
public final class OpenRouterProvider: LLMProvider, @unchecked Sendable {
    public let id = "openrouter"
    public let concurrencyLimit = 8

    private let paidTier = PaidTierCache()

    /// OpenRouter reports the account tier directly, so a paid key needn't discover its headroom by
    /// trial. `GET /api/v1/key` returns `is_free_tier`; anything unknown stays conservative, because
    /// guessing "paid" on a free key means hammering it into 429s.
    public func concurrencyFloor() async -> Int {
        await paidTier.isPaid(apiKey: apiKey, session: session) ? 6 : 3
    }

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

/// One-shot, cached probe of the OpenRouter key tier — this must not add a round trip per batch.
private actor PaidTierCache {
    private var cached: Bool?

    func isPaid(apiKey: String, session: URLSession) async -> Bool {
        if let cached {
            return cached
        }
        guard !apiKey.isEmpty, let url = URL(string: "https://openrouter.ai/api/v1/key") else {
            cached = false
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["data"] as? [String: Any],
              let isFree = payload["is_free_tier"] as? Bool
        else {
            // Unreachable or unparseable: stay at the conservative floor rather than assume headroom.
            cached = false
            return false
        }
        cached = !isFree
        return !isFree
    }
}
