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
    public let concurrencyLimit = 8
    /// Bounded 429 retry budget + per-wait clamp (TASK-463, Electron parity ~4 RL retries).
    static let maxRateLimitRetries = 4
    /// 180 (was 60): honor a legitimate Retry-After up to a couple of minutes rather than retrying
    /// early into a still-active rate limit.
    static let maxRateLimitDelaySeconds: Double = 180

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

        // TASK-481: for a strict `.jsonSchema` request, send Gemini's `generationConfig.responseSchema`
        // (its OpenAPI-3.0 dialect) in addition to JSON mode, so the model is constrained to the field
        // contract — parity with the OpenAI `json_schema` / Anthropic `structuredOutput` paths. Plain
        // `.jsonObject` stays JSON-mode-only (no schema).
        let responseSchema: [String: Any]?
        let wantsJSON: Bool
        switch request.responseFormat {
        case let .jsonSchema(_, schema):
            responseSchema = Self.geminiResponseSchema(fromJSONSchema: schema)
            wantsJSON = true
        case .jsonObject:
            responseSchema = nil
            wantsJSON = true
        case .text, .none:
            responseSchema = nil
            wantsJSON = false
        }

        func makePayload(includeSchema: Bool) -> [String: Any] {
            var payload: [String: Any] = ["contents": contents]
            if wantsJSON {
                var gen: [String: Any] = ["responseMimeType": "application/json"]
                if includeSchema, let responseSchema { gen["responseSchema"] = responseSchema }
                payload["generationConfig"] = gen
            }
            if let sys = systemMsg {
                payload["systemInstruction"] = ["parts": [["text": sys.content]]]
            }
            return payload
        }

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(request.model):generateContent"
        guard let url = URL(string: urlStr) else { throw LLMProviderError.unavailable(reason: "Invalid Google URL") }

        let sentSchema = responseSchema != nil
        var schemaApplied = sentSchema
        var (data, http) = try await send(makePayload(includeSchema: true), to: url)
        // TASK-481 AC#3: Gemini rejects unsupported schema keywords/dialect with a 400. Rather than
        // fail the whole extraction, retry once in plain JSON mode (no responseSchema) — the prompt
        // still instructs the field contract, so this degrades to the pre-481 behavior.
        if http.statusCode == 400, sentSchema {
            schemaApplied = false
            (data, http) = try await send(makePayload(includeSchema: false), to: url)
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

        // Report the format actually used so attempt telemetry is accurate (TASK-565): json_schema
        // when the responseSchema stuck, json_object when JSON mode ran without (or after dropping)
        // the schema, text otherwise.
        let effectiveFormat: ResponseFormat = if !wantsJSON {
            .text
        } else if schemaApplied, case let .jsonSchema(name, schema) = request.responseFormat {
            .jsonSchema(name: name, schema: schema)
        } else {
            .jsonObject
        }

        return ChatResponse(
            content: content,
            model: modelName,
            responseFormat: effectiveFormat,
            promptTokens: decoded.usageMetadata?.promptTokenCount,
            completionTokens: decoded.usageMetadata?.candidatesTokenCount
        )
    }

    /// POSTs `payload` and returns the raw `(data, response)` without throwing on a non-2xx status,
    /// so the caller can branch on it (e.g. the 400 → drop-schema fallback). Maps timeouts to a typed
    /// error and honors 429 here (Gemini doesn't go through OpenAICompatibleTransport): a bounded
    /// retry budget that parses the advised retryDelay, then throws `.rateLimited` so the queue backs
    /// off too (TASK-463).
    private func send(_ payload: [String: Any], to url: URL) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.data(withJSONObject: payload)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Double(timeoutSeconds)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = body

        var rlAttempt = 0
        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch let urlError as URLError where urlError.code == .timedOut {
                throw LLMProviderError.timeout(seconds: timeoutSeconds)
            }
            guard let http = response as? HTTPURLResponse else { throw LLMProviderError.noResponse }
            if http.statusCode == 429 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                let retryAfter = RetryAfterParser.parse(
                    header: http.value(forHTTPHeaderField: "Retry-After"), body: bodyStr, now: Date()
                )
                guard rlAttempt < Self.maxRateLimitRetries else {
                    throw LLMProviderError.rateLimited(retryAfter: retryAfter)
                }
                rlAttempt += 1
                let delay = min(retryAfter ?? pow(2.0, Double(rlAttempt)), Self.maxRateLimitDelaySeconds)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
            return (data, http)
        }
    }

    /// Convert an OpenAI/Anthropic-style JSON Schema string into Gemini's `responseSchema` dialect
    /// (TASK-481). Gemini accepts an OpenAPI-3.0 `Schema` subset that differs from JSON Schema:
    ///   - it **rejects `additionalProperties`** (and we drop the irrelevant `$schema`);
    ///   - nullability is a **`nullable: true`** flag, not a `["type", "null"]` union;
    ///   - `type` is the **uppercase** `Type` enum (STRING/INTEGER/NUMBER/BOOLEAN/ARRAY/OBJECT).
    /// `properties`/`items`/`required` carry over. Returns nil if the input isn't a JSON object, in
    /// which case the caller falls back to plain JSON mode.
    static func geminiResponseSchema(fromJSONSchema jsonString: String) -> [String: Any]? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        return convertSchemaNode(dict) as? [String: Any]
    }

    private static func convertSchemaNode(_ node: Any) -> Any {
        guard let dict = node as? [String: Any] else { return node }
        var out: [String: Any] = [:]
        for (key, value) in dict {
            switch key {
            case "additionalProperties", "$schema":
                continue // unsupported in / irrelevant to Gemini's dialect
            case "type":
                if let types = value as? [String] {
                    let nonNull = types.first { $0 != "null" } ?? "string"
                    out["type"] = nonNull.uppercased()
                    if types.contains("null") { out["nullable"] = true }
                } else if let single = value as? String {
                    out["type"] = single.uppercased()
                } else {
                    out["type"] = value
                }
            case "properties":
                if let props = value as? [String: Any] {
                    out["properties"] = props.mapValues { convertSchemaNode($0) }
                } else {
                    out["properties"] = value
                }
            case "items":
                out["items"] = convertSchemaNode(value)
            default:
                out[key] = value // required, etc. — passes through unchanged
            }
        }
        return out
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
