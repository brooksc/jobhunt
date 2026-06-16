import Foundation

/// Google Generative Language API provider (generateContent).
/// Concurrency limit 3. Returns JSON via responseMimeType.
/// Mirrors postGoogleCompletion() from server/extract.js.
///
/// **API key transport:** uses the `x-goog-api-key` request header rather than a URL query
/// parameter (`?key=`). The header approach keeps credentials out of server-side access logs,
/// proxy logs, and crash reports that may capture URLs. Both transports are accepted by the
/// Google Generative Language v1beta API.
public final class GoogleProvider: LLMProvider, @unchecked Sendable {
    public let id = "google"
    public let concurrencyLimit = 3
    /// Bounded 429 retry budget + per-wait clamp (TASK-463, Electron parity ~4 RL retries).
    static let maxRateLimitRetries = 4
    static let maxRateLimitDelaySeconds: Double = 60

    private let apiKey: String
    private let model: String
    private let timeoutSeconds: Int
    private let session: URLSession

    public init(
        apiKey: String,
        model: String = "",
        timeoutSeconds: Int = 300,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.session = session
    }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let systemMsg = request.messages.first(where: { $0.role == "system" })
        let userMsgs = request.messages.filter { $0.role != "system" }

        let contents = userMsgs.map { msg -> [String: Any] in
            let role = msg.role == "assistant" ? "model" : "user"
            return ["role": role, "parts": [["text": msg.content]]]
        }

        var payload: [String: Any] = ["contents": contents]
        switch request.responseFormat {
        case .jsonObject, .jsonSchema:
            payload["generationConfig"] = ["responseMimeType": "application/json"]
        case .text, .none:
            break
        }
        if let sys = systemMsg {
            payload["systemInstruction"] = ["parts": [["text": sys.content]]]
        }

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(request.model):generateContent"
        guard let url = URL(string: urlStr) else { throw LLMProviderError.unavailable(reason: "Invalid Google URL") }

        let body = try JSONSerialization.data(withJSONObject: payload)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Double(timeoutSeconds)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = body

        // TASK-463: Gemini doesn't go through OpenAICompatibleTransport, so honor 429 here with a
        // bounded retry budget that parses the advised retryDelay; after the budget is spent, throw
        // a typed rateLimited so the queue backs off too.
        var data = Data()
        var http: HTTPURLResponse
        var rlAttempt = 0
        while true {
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch let urlError as URLError where urlError.code == .timedOut {
                throw LLMProviderError.timeout(seconds: timeoutSeconds)
            }
            guard let httpResponse = response as? HTTPURLResponse else { throw LLMProviderError.noResponse }
            http = httpResponse
            if http.statusCode == 429 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                let retryAfter = RetryAfterParser.parse(
                    header: http.value(forHTTPHeaderField: "Retry-After"), body: bodyStr, now: Date())
                guard rlAttempt < Self.maxRateLimitRetries else {
                    throw LLMProviderError.rateLimited(retryAfter: retryAfter)
                }
                rlAttempt += 1
                let delay = min(retryAfter ?? pow(2.0, Double(rlAttempt)), Self.maxRateLimitDelaySeconds)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
            break
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.httpError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(GoogleResponse.self, from: data)
        let content = decoded.candidates?.first?.content?.parts?.first?.text ?? ""
        // TASK-455: a 2xx with no usable candidate text (missing/blocked/empty candidate, e.g. a
        // SAFETY finishReason) is a no-response, not empty success.
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.noResponse
        }
        let modelName = decoded.modelVersion ?? request.model

        return ChatResponse(
            content: content,
            model: modelName,
            responseFormat: .text,
            promptTokens: decoded.usageMetadata?.promptTokenCount,
            completionTokens: decoded.usageMetadata?.candidatesTokenCount
        )
    }
}

// MARK: - Codable

private struct GoogleResponse: Decodable {
    let candidates: [Candidate]?
    let modelVersion: String?
    let usageMetadata: UsageMetadata?

    struct Candidate: Decodable {
        let content: Content?
    }

    struct Content: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }
}
