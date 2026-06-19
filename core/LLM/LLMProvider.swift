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

    /// Stable string for persistence in `LLMRequestAttempt.responseFormat` (TASK-454).
    /// Mirrors the OpenAI `response_format.type` wire values so attempt history reflects
    /// the format the provider actually used (a downgrade shows as "json_object"/"text").
    public var wireValue: String {
        switch self {
        case .jsonSchema: "json_schema"
        case .jsonObject: "json_object"
        case .text: "text"
        }
    }
}

// MARK: - StructuredOutputKind

/// Identifies the expected structured payload so providers that support strict structured output
/// (e.g. Anthropic's `output_config.format`) can enforce a JSON Schema and return guaranteed-valid
/// JSON. Providers that don't support it fall back to `responseFormat`.
public enum StructuredOutputKind: Sendable {
    case jobExtraction
    case fitScore
}

// MARK: - ChatRequest

public struct ChatRequest: Sendable {
    public let messages: [ChatMessage]
    public let model: String
    /// Preferred response format. Providers may negotiate a lower level if unsupported.
    public let responseFormat: ResponseFormat?
    public let maxTokens: Int
    /// Optional guided-generation hint for providers that support typed structured output.
    public let structuredOutput: StructuredOutputKind?

    public init(
        messages: [ChatMessage],
        model: String,
        responseFormat: ResponseFormat? = nil,
        maxTokens: Int = 16384,
        structuredOutput: StructuredOutputKind? = nil
    ) {
        self.messages = messages
        self.model = model
        self.responseFormat = responseFormat
        self.maxTokens = maxTokens
        self.structuredOutput = structuredOutput
    }

    /// A copy with a different model — used for OpenRouter free-model rotation (TASK-462).
    public func replacingModel(_ newModel: String) -> ChatRequest {
        ChatRequest(
            messages: messages, model: newModel, responseFormat: responseFormat,
            maxTokens: maxTokens, structuredOutput: structuredOutput
        )
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
    /// HTTP 429. `retryAfter` is the server-advised wait (seconds), parsed from the Retry-After
    /// header or response body when available (TASK-463).
    case rateLimited(retryAfter: TimeInterval?)

    /// Sanitized description safe for persistence — never includes raw response bodies.
    public var errorDescription: String? {
        switch self {
        case let .httpError(code, _):
            "LLM HTTP \(code)"
        case let .timeout(seconds):
            "LLM request timed out after \(seconds)s"
        case .noResponse:
            "LLM produced no response"
        case let .unavailable(reason):
            "LLM provider unavailable: \(reason)"
        case let .rateLimited(retryAfter):
            retryAfter.map { "LLM rate limited (retry after \(Int($0))s)" } ?? "LLM rate limited (HTTP 429)"
        }
    }
}

// MARK: - RetryAfterParser (TASK-463)

/// Pure parsing of a server-advised rate-limit wait from a `Retry-After` header and/or a response
/// body hint (OpenAI "retry … in Ns", Gemini `retryDelay: "Ns"`). Returns seconds to wait, or nil.
public enum RetryAfterParser {
    public static func parse(header: String?, body: String?, now: Date) -> TimeInterval? {
        if let value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            // Either delta-seconds (most common) or an HTTP-date.
            if let seconds = Double(value) { return max(0, seconds) }
            if let date = httpDate(value) { return max(0, date.timeIntervalSince(now)) }
        }
        if let body, let seconds = secondsFromBody(body) { return seconds }
        return nil
    }

    /// Match Gemini `"retryDelay": "30s"` and OpenAI-style "try again in 1.5s" / "retry in 20 seconds".
    private static func secondsFromBody(_ body: String) -> TimeInterval? {
        let patterns = [
            #""retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s""#,
            #"(?:retry|try again)[^0-9]{0,20}?(\d+(?:\.\d+)?)\s*(?:s\b|sec|second)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = body as NSString
            if let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1,
               let value = Double(ns.substring(with: match.range(at: 1))) {
                return max(0, value)
            }
        }
        return nil
    }

    private static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
