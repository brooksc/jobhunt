import Foundation

/// Custom OpenAI-compatible provider with a user-configured base URL.
/// Concurrency limit 2 (local or unknown endpoint).
public final class CustomProvider: LLMProvider, @unchecked Sendable {
    public let id = "custom"
    public let concurrencyLimit = 2

    private let baseURL: String
    private let apiKey: String
    private let model: String
    private let timeoutSeconds: Int
    private let session: URLSession

    public init(
        baseURL: String,
        apiKey: String = "",
        model: String,
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
