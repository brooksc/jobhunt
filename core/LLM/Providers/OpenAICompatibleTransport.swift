// swiftlint:disable function_body_length nesting
import Foundation

/// Shared transport logic for all OpenAI-compatible providers
/// (LM Studio, OpenAI, OpenRouter, Custom).
/// Mirrors postOpenAICompatibleCompletion() from server/extract.js including
/// the json_schema → json_object → text format-negotiation ladder.
enum OpenAICompatibleTransport {
    /// Sends a chat-completion request using the negotiation ladder.
    /// On HTTP 400, tries the next format level; throws on other errors.
    static func complete(
        request: ChatRequest,
        baseURL: String,
        apiKey: String,
        providerID _: String,
        extraHeaders: [String: String] = [:],
        session: URLSession = .shared,
        timeoutSeconds: Int = 300
    ) async throws -> ChatResponse {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMProviderError.httpError(statusCode: 0, body: "Invalid base URL: \(baseURL)")
        }

        var headers = ["Content-Type": "application/json"]
        if !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        for (headerKey, headerVal) in extraHeaders {
            headers[headerKey] = headerVal
        }

        // Build the format negotiation ladder: preferred → json_object → nil (text)
        var formats: [ResponseFormat?] = [nil, nil, nil]
        switch request.responseFormat {
        case .jsonSchema:
            formats = [request.responseFormat, .jsonObject, nil]
        case .jsonObject:
            formats = [.jsonObject, nil]
        case .text, .none:
            formats = [nil]
        }

        var lastBadStatusCode: Int?
        var lastBadBody: String?

        for fmt in formats {
            let body = try buildBody(request: request, fmt: fmt)
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = Double(timeoutSeconds)
            for (headerKey, headerVal) in headers {
                urlRequest.setValue(headerVal, forHTTPHeaderField: headerKey)
            }
            urlRequest.httpBody = body

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch let urlError as URLError where urlError.code == .timedOut {
                throw LLMProviderError.timeout(seconds: timeoutSeconds)
            }
            guard let http = response as? HTTPURLResponse else {
                throw LLMProviderError.noResponse
            }

            if http.statusCode == 400 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                let isFormatError = bodyStr.localizedCaseInsensitiveContains("response_format")
                    || bodyStr.localizedCaseInsensitiveContains("json_schema")
                    || bodyStr.localizedCaseInsensitiveContains("json_object")
                if !isFormatError {
                    throw LLMProviderError.httpError(statusCode: 400, body: bodyStr)
                }
                lastBadStatusCode = 400
                lastBadBody = bodyStr
                // Try next format level
                continue
            }
            if http.statusCode == 429 {
                // TASK-463: surface a typed rate-limit error carrying the server-advised wait so the
                // queue can honor Retry-After instead of generic exponential backoff.
                let body = String(data: data, encoding: .utf8) ?? ""
                let retryAfter = RetryAfterParser.parse(
                    header: http.value(forHTTPHeaderField: "Retry-After"), body: body, now: Date()
                )
                throw LLMProviderError.rateLimited(retryAfter: retryAfter)
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw LLMProviderError.httpError(statusCode: http.statusCode, body: body)
            }

            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            let content = decoded.choices.first?.message.content ?? ""
            // TASK-455: a 2xx with no usable choice/message content is a no-response, not empty
            // success — classify it at the boundary instead of failing later as a JSON parse error.
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMProviderError.noResponse
            }
            let modelName = decoded.model ?? request.model
            let usedFormat = fmt ?? .text
            return ChatResponse(
                content: content,
                model: modelName,
                responseFormat: usedFormat,
                promptTokens: decoded.usage?.promptTokens,
                completionTokens: decoded.usage?.completionTokens
            )
        }

        if let code = lastBadStatusCode {
            throw LLMProviderError.httpError(statusCode: code, body: lastBadBody ?? "")
        }
        throw LLMProviderError.noResponse
    }

    // MARK: - Private

    private static func buildBody(request: ChatRequest, fmt: ResponseFormat?) throws -> Data {
        var obj: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0,
            "stream": false,
            "max_tokens": request.maxTokens
        ]
        if let fmt {
            obj["response_format"] = responseFormatJSON(fmt)
        }
        return try JSONSerialization.data(withJSONObject: obj)
    }

    static func responseFormatJSON(_ fmt: ResponseFormat) -> [String: Any] {
        switch fmt {
        case let .jsonSchema(name, schema):
            // Parse schema string back to JSON object for embedding
            let schemaObj = (try? JSONSerialization.jsonObject(with: Data(schema.utf8))) ?? [String: Any]()
            return [
                "type": "json_schema",
                "json_schema": [
                    "name": name,
                    "strict": true,
                    "schema": schemaObj
                ]
            ]
        case .jsonObject:
            return ["type": "json_object"]
        case .text:
            return [:]
        }
    }
}

// MARK: - Codable response models

struct OpenAIChatResponse: Decodable {
    let model: String?
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}

// swiftlint:enable cyclomatic_complexity function_body_length nesting
