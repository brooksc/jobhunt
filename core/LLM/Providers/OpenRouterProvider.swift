import Foundation

/// OpenRouter provider — OpenAI-compatible API at openrouter.ai.
/// Concurrency limit 3. Adds OpenRouter-specific HTTP headers.
/// Mirrors postOpenAICompatibleCompletion() with openrouter base URL.
public final class OpenRouterProvider: LLMProvider, @unchecked Sendable {
    public let id = "openrouter"
    public let concurrencyLimit = 3

    private let apiKey: String
    private let model: String
    private let timeoutSeconds: Int
    private let session: URLSession

    public init(
        apiKey: String,
        model: String = "openai/gpt-4o",
        timeoutSeconds: Int = 300,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.session = session
    }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let extraHeaders: [String: String] = [
            "HTTP-Referer": "https://github.com/jobhunt-app/jobhunt",
            "X-Title": "Jobhunt",
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
