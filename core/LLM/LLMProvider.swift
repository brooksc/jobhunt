import Foundation

// MARK: - ChatMessage

public struct ChatMessage: Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - ResponseFormat

public enum ResponseFormat: Sendable, Equatable {
    /// JSON Schema (strict) — sent as response_format.type=json_schema
    case jsonSchema(name: String, schema: String)
    /// Plain JSON object — sent as response_format.type=json_object
    case jsonObject
    /// No structured format — model returns free text; prompt must instruct JSON
    case text
}

// MARK: - ChatRequest

public struct ChatRequest: Sendable {
    public let messages: [ChatMessage]
    public let model: String
    /// Preferred response format. Providers may negotiate a lower level if unsupported.
    public let responseFormat: ResponseFormat?
    public let maxTokens: Int

    public init(
        messages: [ChatMessage],
        model: String,
        responseFormat: ResponseFormat? = nil,
        maxTokens: Int = 16384
    ) {
        self.messages = messages
        self.model = model
        self.responseFormat = responseFormat
        self.maxTokens = maxTokens
    }
}

// MARK: - ChatResponse

public struct ChatResponse: Sendable {
    /// The text content returned by the model.
    public let content: String
    /// The model identifier as reported by the provider.
    public let model: String
    /// The format actually used for this response (may be lower than requested).
    public let responseFormat: ResponseFormat
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(
        content: String,
        model: String,
        responseFormat: ResponseFormat,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.content = content
        self.model = model
        self.responseFormat = responseFormat
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

// MARK: - LLMProvider protocol

public protocol LLMProvider: Sendable {
    /// A stable string identifier for this provider (e.g. "openai", "anthropic").
    var id: String { get }
    /// Maximum number of concurrent in-flight requests this provider can handle.
    var concurrencyLimit: Int { get }
    /// Send a chat completion request and return the response.
    func complete(_ request: ChatRequest) async throws -> ChatResponse
}

// MARK: - LLMProviderError

public enum LLMProviderError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)
    case timeout(seconds: Int)
    case noResponse
    case unavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .httpError(code, body):
            "LLM HTTP \(code): \(body.prefix(500))"
        case let .timeout(seconds):
            "LLM request timed out after \(seconds)s"
        case .noResponse:
            "LLM produced no response"
        case let .unavailable(reason):
            "LLM provider unavailable: \(reason)"
        }
    }
}
