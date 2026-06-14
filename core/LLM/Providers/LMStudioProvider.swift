import Foundation

/// OpenAI-compatible provider for LM Studio (default local provider).
/// POSTs to /v1/chat/completions on the configured base URL.
/// Mirrors postOpenAICompatibleCompletion() in server/extract.js.
public final class LMStudioProvider: LLMProvider, @unchecked Sendable {
    public let id = "lmstudio"
    public let concurrencyLimit = 1

    private let baseURL: String
    private let apiKey: String
    private let model: String
    private let timeoutSeconds: Int
    private let session: URLSession

    public init(
        baseURL: String = "http://127.0.0.1:1234",
        apiKey: String = "",
        model: String = "",
        timeoutSeconds: Int = 300,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.session = session
    }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        try await OpenAICompatibleTransport.complete(
            request: request,
            baseURL: baseURL,
            apiKey: apiKey,
            providerID: id,
            session: session,
            timeoutSeconds: timeoutSeconds
        )
    }
}
