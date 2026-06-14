import Foundation

/// OpenAI provider (api.openai.com).
/// Concurrency limit 3 to mirror legacy HOSTED_CONCURRENCY.
public final class OpenAIProvider: LLMProvider, @unchecked Sendable {
    public let id = "openai"
    public let concurrencyLimit = 3

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
        try await OpenAICompatibleTransport.complete(
            request: request,
            baseURL: "https://api.openai.com",
            apiKey: apiKey,
            providerID: id,
            session: session,
            timeoutSeconds: timeoutSeconds
        )
    }
}
