// swiftlint:disable nesting
import Foundation

/// Anthropic Messages API provider.
/// Uses x-api-key header; maps to /v1/messages; concurrency limit 2.
/// Mirrors postAnthropicCompletion() from server/extract.js.
///
/// Structured output: when the request carries a `structuredOutput` kind (or an explicit
/// `.jsonSchema` response format), the provider sends Anthropic's `output_config.format`
/// json_schema so the first content block is guaranteed valid JSON. Models that don't support
/// it (older Claude) return HTTP 400 for the format field; we retry once without it and let the
/// engine's JSON repair handle the free-form text.
public final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    public let id = "anthropic"
    public let concurrencyLimit = 2

    private let apiKey: String
    private let model: String
    private let timeoutSeconds: Int
    private let session: URLSession

    /// `model` is informational only — the model actually sent is `ChatRequest.model`. It carries
    /// no hardcoded default; the empty default keeps test/init sites that don't care concise.
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

        var payload: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "messages": userMsgs.map { ["role": $0.role, "content": $0.content] }
        ]
        if let sys = systemMsg { payload["system"] = sys.content }

        let schema = structuredOutputSchema(for: request)
        if let schema {
            // Parse the schema string into an object for embedding; the first content block is
            // then guaranteed valid JSON matching the schema. No beta header is required.
            let schemaObj = (try? JSONSerialization.jsonObject(with: Data(schema.utf8))) ?? [String: Any]()
            payload["output_config"] = ["format": ["type": "json_schema", "schema": schemaObj]]
        }

        do {
            return try await send(payload: payload, usedSchema: schema != nil)
        } catch let LLMProviderError.httpError(statusCode, body) where statusCode == 400
            && schema != nil && isStructuredOutputError(body) {
            // Model doesn't support output_config.format — retry as free-form text + JSON repair.
            payload.removeValue(forKey: "output_config")
            return try await send(payload: payload, usedSchema: false)
        }
    }

    // MARK: - Private

    private func send(payload: [String: Any], usedSchema: Bool) async throws -> ChatResponse {
        let body = try JSONSerialization.data(withJSONObject: payload)
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Double(timeoutSeconds)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw LLMProviderError.timeout(seconds: timeoutSeconds)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMProviderError.noResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.httpError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = decoded.content?.first?.text ?? ""
        // TASK-455: a 2xx with no usable text content block (e.g. a stop/refusal with no text) is a
        // no-response, not empty success.
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.noResponse
        }
        let modelName = decoded.model ?? (payload["model"] as? String ?? "")

        return ChatResponse(
            content: content,
            model: modelName,
            responseFormat: usedSchema ? .jsonObject : .text,
            promptTokens: decoded.usage?.inputTokens,
            completionTokens: decoded.usage?.outputTokens
        )
    }

    /// Resolves the JSON Schema to enforce: the structured-output kind takes precedence, falling
    /// back to an explicit `.jsonSchema` response format if one was supplied.
    private func structuredOutputSchema(for request: ChatRequest) -> String? {
        if let kind = request.structuredOutput {
            return StructuredOutputSchemas.schema(for: kind).schema
        }
        if case let .jsonSchema(_, schema) = request.responseFormat {
            return schema
        }
        return nil
    }

    private func isStructuredOutputError(_ body: String) -> Bool {
        body.localizedCaseInsensitiveContains("output_config")
            || body.localizedCaseInsensitiveContains("json_schema")
            || body.localizedCaseInsensitiveContains("format")
    }
}

// MARK: - Codable

private struct AnthropicResponse: Decodable {
    let model: String?
    let content: [ContentBlock]?
    let usage: Usage?

    struct ContentBlock: Decodable {
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

// swiftlint:enable nesting
