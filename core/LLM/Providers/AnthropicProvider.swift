// swiftlint:disable nesting
import Foundation

/// Anthropic Messages API provider.
/// Uses x-api-key header; maps to /v1/messages; concurrency limit 2.
/// Mirrors postAnthropicCompletion() from server/extract.js.
/// Note: Anthropic does not support structured response_format — always returns text.
public final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    public let id = "anthropic"
    public let concurrencyLimit = 2

    private let apiKey: String
    private let model: String
    private let timeoutSeconds: Int
    private let session: URLSession

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
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

        let body = try JSONSerialization.data(withJSONObject: payload)
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Double(timeoutSeconds)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = body

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw LLMProviderError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.httpError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = decoded.content?.first?.text ?? ""
        let modelName = decoded.model ?? request.model

        return ChatResponse(
            content: content,
            model: modelName,
            responseFormat: .text,
            promptTokens: decoded.usage?.inputTokens,
            completionTokens: decoded.usage?.outputTokens
        )
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
