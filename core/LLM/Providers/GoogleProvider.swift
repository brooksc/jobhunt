import Foundation

/// Google Generative Language API provider (generateContent).
/// Concurrency limit 3. Returns JSON via responseMimeType.
/// Mirrors postGoogleCompletion() from server/extract.js.
public final class GoogleProvider: LLMProvider, @unchecked Sendable {
    public let id = "google"
    public let concurrencyLimit = 3

    private let apiKey: String
    private let model: String
    private let timeoutSeconds: Int
    private let session: URLSession

    public init(
        apiKey: String,
        model: String = "gemini-2.5-flash",
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

        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": ["responseMimeType": "application/json"]
        ]
        if let sys = systemMsg {
            payload["systemInstruction"] = ["parts": [["text": sys.content]]]
        }

        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(request.model):generateContent?key=\(encodedKey)"
        guard let url = URL(string: urlStr) else { throw LLMProviderError.unavailable(reason: "Invalid Google URL") }

        let body = try JSONSerialization.data(withJSONObject: payload)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Double(timeoutSeconds)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw LLMProviderError.noResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.httpError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(GoogleResponse.self, from: data)
        let content = decoded.candidates?.first?.content?.parts?.first?.text ?? ""
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
