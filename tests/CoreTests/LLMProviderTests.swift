// swiftlint:disable force_unwrapping file_length
import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - LLMMockURLProtocol

/// Records captured requests and returns preconfigured responses.
/// Named LLMMockURLProtocol to avoid conflict with MockURLProtocol in AvailabilityCheckerTests.
///
/// Static state is global — these tests must not run in parallel within the same process.
/// Provider test classes inherit LLMMockProviderTestCase which calls reset() in both setUp and tearDown.
final class LLMMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var capturedRequests: [URLRequest] = []

    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        LLMMockURLProtocol.capturedRequests.append(request)
        guard let handler = LLMMockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "LLMMockURLProtocol", code: 0))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LLMMockURLProtocol.self]
    return URLSession(configuration: config)
}

/// Reads the body from a URLRequest, checking both httpBody and httpBodyStream.
private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    if let stream = request.httpBodyStream {
        stream.open()
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate(); stream.close() }
        var bytesRead: Int
        repeat {
            bytesRead = stream.read(buffer, maxLength: 4096)
            if bytesRead > 0 { data.append(buffer, count: bytesRead) }
        } while bytesRead > 0
        return data.isEmpty ? nil : data
    }
    return nil
}

private func openAIResponse(content: String, model: String = "gpt-4o") -> Data {
    let json = """
    {
      "model": "\(model)",
      "choices": [{"message": {"content": "\(content)"}}],
      "usage": {"prompt_tokens": 100, "completion_tokens": 50}
    }
    """
    return Data(json.utf8)
}

private func mockHTTPResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

// MARK: - Shared base for provider tests that use LLMMockURLProtocol

/// Resets LLMMockURLProtocol state in both setUp and tearDown to prevent
/// cross-test handler leakage, including when a test exits early via throw.
class LLMMockProviderTestCase: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.reset()
        session = makeMockSession()
    }

    override func tearDown() {
        LLMMockURLProtocol.reset()
        session = nil
        super.tearDown()
    }
}

// MARK: - OpenAI provider tests

final class OpenAIProviderTests: LLMMockProviderTestCase {
    func testRequestURLAndHeaders() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let response = mockHTTPResponse(url: req.url!)
            return (response, openAIResponse(content: "hello"))
        }
        let provider = OpenAIProvider(apiKey: "sk-test", model: "gpt-4o", session: session)
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "gpt-4o")

        let result = try await provider.complete(req)

        let captured = LLMMockURLProtocol.capturedRequests.first
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(result.content, "hello")
        XCTAssertEqual(result.model, "gpt-4o")
        // TASK-538: provider-reported token usage is surfaced on ChatResponse.
        XCTAssertEqual(result.promptTokens, 100)
        XCTAssertEqual(result.completionTokens, 50)
    }

    func testConcurrencyLimit() {
        let provider = OpenAIProvider(apiKey: "sk-test")
        XCTAssertEqual(provider.concurrencyLimit, 3)
    }

    // TASK-455: a 2xx with empty message content is a no-response, not empty success.
    func testEmptyContentThrowsNoResponse() async {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), openAIResponse(content: ""))
        }
        let provider = OpenAIProvider(apiKey: "sk-test", session: session)
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "gpt-4o")
        do {
            _ = try await provider.complete(req)
            XCTFail("expected LLMProviderError.noResponse")
        } catch LLMProviderError.noResponse {
            // expected
        } catch {
            XCTFail("expected noResponse, got \(error)")
        }
    }

    func testProviderID() {
        XCTAssertEqual(OpenAIProvider(apiKey: "").id, "openai")
    }

    func testFormatNegotiationFallsBackToJsonObject() async throws {
        var callCount = 0
        LLMMockURLProtocol.requestHandler = { req in
            callCount += 1
            let body = try JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            let fmt = body?["response_format"] as? [String: Any]

            if callCount == 1 {
                // First call: json_schema → return 400 with format error body
                XCTAssertEqual(fmt?["type"] as? String, "json_schema")
                let errBody = Data("{\"error\":{\"message\":\"response_format type json_schema not supported\"}}".utf8)
                return (mockHTTPResponse(url: req.url!, statusCode: 400), errBody)
            } else {
                // Second call: json_object → return 200
                XCTAssertEqual(fmt?["type"] as? String, "json_object")
                return (mockHTTPResponse(url: req.url!), openAIResponse(content: "{}"))
            }
        }

        let provider = OpenAIProvider(apiKey: "sk-test", session: session)
        let schema = ChatRequest(
            messages: [ChatMessage(role: "user", content: "extract")],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "extracted_job", schema: "{\"type\":\"object\"}")
        )
        let result = try await provider.complete(schema)
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(result.responseFormat, .jsonObject)
    }

    func testFormatNegotiationFallsBackToText() async throws {
        var callCount = 0
        LLMMockURLProtocol.requestHandler = { req in
            callCount += 1
            if callCount <= 2 {
                let errBody = Data("{\"error\":{\"message\":\"response_format not supported\"}}".utf8)
                return (mockHTTPResponse(url: req.url!, statusCode: 400), errBody)
            }
            // Third call: no format → text
            let body = try JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            XCTAssertNil(body?["response_format"])
            return (mockHTTPResponse(url: req.url!), openAIResponse(content: "plain text"))
        }

        let provider = OpenAIProvider(apiKey: "sk-test", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "go")],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "x", schema: "{}")
        )
        let result = try await provider.complete(req)
        XCTAssertEqual(callCount, 3)
        XCTAssertEqual(result.responseFormat, .text)
        XCTAssertEqual(result.content, "plain text")
    }
}

// MARK: - Anthropic provider tests

final class AnthropicProviderTests: LLMMockProviderTestCase {
    private func anthropicResponse(text: String, model: String = "claude-sonnet-4-6") -> Data {
        let json = """
        {
          "model": "\(model)",
          "content": [{"type": "text", "text": "\(text)"}],
          "usage": {"input_tokens": 80, "output_tokens": 40}
        }
        """
        return Data(json.utf8)
    }

    // TASK-455: a 2xx with no usable text content block is a no-response.
    func testEmptyContentThrowsNoResponse() async {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), Data("{\"model\":\"claude-sonnet-4-6\",\"content\":[]}".utf8))
        }
        let provider = AnthropicProvider(apiKey: "ant-key", model: "claude-sonnet-4-6", session: session)
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "claude-sonnet-4-6")
        do {
            _ = try await provider.complete(req)
            XCTFail("expected LLMProviderError.noResponse")
        } catch LLMProviderError.noResponse {
            // expected
        } catch {
            XCTFail("expected noResponse, got \(error)")
        }
    }

    func testRequestURLAndHeaders() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), self.anthropicResponse(text: "result"))
        }
        let provider = AnthropicProvider(apiKey: "ant-key", model: "claude-sonnet-4-6", session: session)
        let req = ChatRequest(
            messages: [
                ChatMessage(role: "system", content: "sys"),
                ChatMessage(role: "user", content: "user")
            ],
            model: "claude-sonnet-4-6"
        )
        let result = try await provider.complete(req)

        let captured = try XCTUnwrap(LLMMockURLProtocol.capturedRequests.first)
        XCTAssertEqual(captured.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "x-api-key"), "ant-key")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(result.content, "result")
        XCTAssertEqual(result.responseFormat, .text)
        // TASK-538: non-OpenAI provider token usage is surfaced too (Anthropic input/output tokens).
        XCTAssertEqual(result.promptTokens, 80)
        XCTAssertEqual(result.completionTokens, 40)
    }

    func testSystemMessageExtracted() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let body = try JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            XCTAssertEqual(body?["system"] as? String, "Be helpful")
            let messages = body?["messages"] as? [[String: Any]]
            XCTAssertEqual(messages?.count, 1)
            XCTAssertEqual(messages?.first?["role"] as? String, "user")
            return (mockHTTPResponse(url: req.url!), self.anthropicResponse(text: "ok"))
        }

        let provider = AnthropicProvider(apiKey: "k", session: session)
        let req = ChatRequest(
            messages: [
                ChatMessage(role: "system", content: "Be helpful"),
                ChatMessage(role: "user", content: "Hello")
            ],
            model: "claude-sonnet-4-6"
        )
        _ = try await provider.complete(req)
    }

    // TASK-565: a successful strict-schema call records json_schema (was json_object).
    func testStrictSchemaSuccessReportsJSONSchema() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), self.anthropicResponse(text: "{}"))
        }
        let provider = AnthropicProvider(apiKey: "k", model: "claude-sonnet-4-6", session: session)
        let format = ResponseFormat.jsonSchema(name: "job", schema: "{\"type\":\"object\"}")
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "claude-sonnet-4-6",
            responseFormat: format
        )
        let result = try await provider.complete(req)
        XCTAssertEqual(result.responseFormat, format)
    }

    // TASK-565: when the model rejects output_config (400), the text-fallback retry records text.
    func testStructuredOutputFallbackReportsText() async throws {
        var calls = 0
        LLMMockURLProtocol.requestHandler = { req in
            calls += 1
            if calls == 1 {
                return (
                    mockHTTPResponse(url: req.url!, statusCode: 400),
                    Data("{\"error\":\"output_config not supported\"}".utf8)
                )
            }
            return (mockHTTPResponse(url: req.url!), self.anthropicResponse(text: "{}"))
        }
        let provider = AnthropicProvider(apiKey: "k", model: "claude-sonnet-4-6", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "claude-sonnet-4-6",
            responseFormat: .jsonSchema(name: "job", schema: "{\"type\":\"object\"}")
        )
        let result = try await provider.complete(req)
        XCTAssertEqual(result.responseFormat, .text)
    }

    // TASK-539: Anthropic 429 maps to a typed rate-limit error with the advised wait (was httpError).
    func test429WithRetryAfterThrowsRateLimited() async {
        LLMMockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "30"]
            )!
            return (resp, Data("{\"error\":\"rate limited\"}".utf8))
        }
        let provider = AnthropicProvider(apiKey: "k", model: "claude-sonnet-4-6", session: session)
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "claude-sonnet-4-6")
        do {
            _ = try await provider.complete(req)
            XCTFail("expected rateLimited")
        } catch let LLMProviderError.rateLimited(retryAfter) {
            XCTAssertEqual(retryAfter, 30)
        } catch {
            XCTFail("expected rateLimited, got \(error)")
        }
    }

    func test429WithoutRetryAfterStillThrowsRateLimited() async {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!, statusCode: 429), Data("{\"error\":\"slow down\"}".utf8))
        }
        let provider = AnthropicProvider(apiKey: "k", model: "claude-sonnet-4-6", session: session)
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "claude-sonnet-4-6")
        do {
            _ = try await provider.complete(req)
            XCTFail("expected rateLimited")
        } catch LLMProviderError.rateLimited {
            // expected — retryAfter may be nil
        } catch {
            XCTFail("expected rateLimited, got \(error)")
        }
    }

    func testConcurrencyLimit() {
        XCTAssertEqual(AnthropicProvider(apiKey: "").concurrencyLimit, 2)
    }
}

// MARK: - Google provider tests

final class GoogleProviderTests: LLMMockProviderTestCase {
    private func googleResponse(text: String) -> Data {
        let json = """
        {
          "candidates": [{"content": {"parts": [{"text": "\(text)"}]}}],
          "modelVersion": "gemini-2.5-flash-001"
        }
        """
        return Data(json.utf8)
    }

    // TASK-455: a 2xx with no usable candidate text (e.g. a blocked/empty candidate) is a no-response.
    func testEmptyCandidateThrowsNoResponse() async {
        LLMMockURLProtocol.requestHandler = { req in
            // No candidates at all (e.g. blocked by safety) — must classify as no-response.
            (mockHTTPResponse(url: req.url!), Data("{\"candidates\":[],\"modelVersion\":\"x\"}".utf8))
        }
        let provider = GoogleProvider(apiKey: "gkey", model: "gemini-2.5-flash", session: session)
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "gemini-2.5-flash")
        do {
            _ = try await provider.complete(req)
            XCTFail("expected LLMProviderError.noResponse")
        } catch LLMProviderError.noResponse {
            // expected
        } catch {
            XCTFail("expected noResponse, got \(error)")
        }
    }

    func testRequestURLContainsModel_andKeyIsInHeader() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), self.googleResponse(text: "answer"))
        }
        let provider = GoogleProvider(apiKey: "gkey", model: "gemini-2.5-flash", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "gemini-2.5-flash"
        )
        _ = try await provider.complete(req)

        let captured = try XCTUnwrap(LLMMockURLProtocol.capturedRequests.first)
        let urlStr = captured.url?.absoluteString ?? ""
        XCTAssertTrue(urlStr.contains("gemini-2.5-flash:generateContent"), "URL must contain model name")
        XCTAssertFalse(urlStr.contains("key="), "API key must NOT appear in URL query (TASK-128)")
        XCTAssertEqual(
            captured.value(forHTTPHeaderField: "x-goog-api-key"),
            "gkey",
            "API key must be sent via x-goog-api-key header"
        )
    }

    func testSystemInstructionInjected() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let body = try JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            XCTAssertNotNil(body?["systemInstruction"])
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "x"))
        }
        let provider = GoogleProvider(apiKey: "k", session: session)
        let req = ChatRequest(
            messages: [
                ChatMessage(role: "system", content: "sys"),
                ChatMessage(role: "user", content: "q")
            ],
            model: "gemini-2.5-flash"
        )
        _ = try await provider.complete(req)
    }

    // TASK-565: Google reported .text regardless of what it sent. Now it reports the effective format.
    func testStrictSchemaSuccessReportsJSONSchema() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), self.googleResponse(text: "{}"))
        }
        let provider = GoogleProvider(apiKey: "gkey", model: "gemini-2.5-flash", session: session)
        let format = ResponseFormat.jsonSchema(name: "job", schema: "{\"type\":\"object\"}")
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "gemini-2.5-flash",
            responseFormat: format
        )
        let result = try await provider.complete(req)
        XCTAssertEqual(result.responseFormat, format)
    }

    func testJSONObjectModeReportsJSONObject() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), self.googleResponse(text: "{}"))
        }
        let provider = GoogleProvider(apiKey: "gkey", model: "gemini-2.5-flash", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "gemini-2.5-flash",
            responseFormat: .jsonObject
        )
        let result = try await provider.complete(req)
        XCTAssertEqual(result.responseFormat, .jsonObject)
    }

    /// Schema rejected (400) → JSON-mode retry → records json_object, not json_schema.
    func testSchemaRejected400ReportsJSONObject() async throws {
        var calls = 0
        LLMMockURLProtocol.requestHandler = { req in
            calls += 1
            if calls == 1 {
                return (mockHTTPResponse(url: req.url!, statusCode: 400), Data("{\"error\":\"bad schema\"}".utf8))
            }
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "{}"))
        }
        let provider = GoogleProvider(apiKey: "gkey", model: "gemini-2.5-flash", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "gemini-2.5-flash",
            responseFormat: .jsonSchema(name: "job", schema: "{\"type\":\"object\"}")
        )
        let result = try await provider.complete(req)
        XCTAssertEqual(result.responseFormat, .jsonObject)
    }

    func testPlainTextReportsText() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), self.googleResponse(text: "hello"))
        }
        let provider = GoogleProvider(apiKey: "gkey", model: "gemini-2.5-flash", session: session)
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "gemini-2.5-flash")
        let result = try await provider.complete(req)
        XCTAssertEqual(result.responseFormat, .text)
    }

    func testConcurrencyLimit() {
        XCTAssertEqual(GoogleProvider(apiKey: "").concurrencyLimit, 3)
    }

    // MARK: - TASK-481: strict structured output via responseSchema

    /// AC#2: the converted schema drops `additionalProperties`, expresses `["string","null"]`
    /// nullability as a `nullable: true` flag, and uppercases types to Gemini's `Type` enum.
    func testGeminiSchemaConversion_dialectTransform() throws {
        let (_, schema) = StructuredOutputSchemas.schema(for: .jobExtraction)
        let converted = try XCTUnwrap(GoogleProvider.geminiResponseSchema(fromJSONSchema: schema))

        XCTAssertEqual(converted["type"] as? String, "OBJECT")
        XCTAssertNil(converted["additionalProperties"], "Gemini rejects additionalProperties")

        let props = try XCTUnwrap(converted["properties"] as? [String: Any])
        // A nullable scalar: ["string","null"] -> type STRING + nullable true.
        let company = try XCTUnwrap(props["company"] as? [String: Any])
        XCTAssertEqual(company["type"] as? String, "STRING")
        XCTAssertEqual(company["nullable"] as? Bool, true)
        // A non-null array of strings: type ARRAY, items type STRING, no nullable flag.
        let skills = try XCTUnwrap(props["skills"] as? [String: Any])
        XCTAssertEqual(skills["type"] as? String, "ARRAY")
        XCTAssertNil(skills["nullable"])
        let skillItems = try XCTUnwrap(skills["items"] as? [String: Any])
        XCTAssertEqual(skillItems["type"] as? String, "STRING")
    }

    /// AC#2: nested objects (fit-score `dimensions[].…`) are converted recursively — the inner
    /// object also loses `additionalProperties` and gets uppercased types.
    func testGeminiSchemaConversion_recursesIntoArrayItems() throws {
        let (_, schema) = StructuredOutputSchemas.schema(for: .fitScore)
        let converted = try XCTUnwrap(GoogleProvider.geminiResponseSchema(fromJSONSchema: schema))
        let props = try XCTUnwrap(converted["properties"] as? [String: Any])
        let dimensions = try XCTUnwrap(props["dimensions"] as? [String: Any])
        let item = try XCTUnwrap(dimensions["items"] as? [String: Any])
        XCTAssertEqual(item["type"] as? String, "OBJECT")
        XCTAssertNil(item["additionalProperties"], "nested object must also drop additionalProperties")
        let itemProps = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertEqual((itemProps["score"] as? [String: Any])?["type"] as? String, "INTEGER")
    }

    func testGeminiSchemaConversion_invalidJSONReturnsNil() {
        XCTAssertNil(GoogleProvider.geminiResponseSchema(fromJSONSchema: "not json"))
    }

    /// AC#1: a `.jsonSchema` request sends `generationConfig.responseSchema` alongside JSON mode.
    func testJSONSchemaRequest_sendsResponseSchema() async throws {
        var capturedGen: [String: Any]?
        LLMMockURLProtocol.requestHandler = { req in
            let body = try? JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            capturedGen = body?["generationConfig"] as? [String: Any]
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "{}"))
        }
        let provider = GoogleProvider(apiKey: "k", model: "gemini-2.5-flash", session: session)
        let (name, schema) = StructuredOutputSchemas.schema(for: .jobExtraction)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "q")],
            model: "gemini-2.5-flash",
            responseFormat: .jsonSchema(name: name, schema: schema)
        )
        _ = try await provider.complete(req)

        let gen = try XCTUnwrap(capturedGen)
        XCTAssertEqual(gen["responseMimeType"] as? String, "application/json")
        let sentSchema = try XCTUnwrap(gen["responseSchema"] as? [String: Any])
        XCTAssertEqual(sentSchema["type"] as? String, "OBJECT")
        XCTAssertNil(sentSchema["additionalProperties"])
    }

    /// `.jsonObject` stays JSON-mode-only — no responseSchema.
    func testJSONObjectRequest_omitsResponseSchema() async throws {
        var capturedGen: [String: Any]?
        LLMMockURLProtocol.requestHandler = { req in
            let body = try? JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            capturedGen = body?["generationConfig"] as? [String: Any]
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "{}"))
        }
        let provider = GoogleProvider(apiKey: "k", model: "gemini-2.5-flash", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "q")],
            model: "gemini-2.5-flash",
            responseFormat: .jsonObject
        )
        _ = try await provider.complete(req)

        let gen = try XCTUnwrap(capturedGen)
        XCTAssertEqual(gen["responseMimeType"] as? String, "application/json")
        XCTAssertNil(gen["responseSchema"], ".jsonObject must not send a strict schema")
    }

    /// AC#3: if Gemini rejects the responseSchema with 400, retry once in plain JSON mode and succeed.
    func testResponseSchemaRejected400_fallsBackToJSONMode() async throws {
        var callCount = 0
        var secondHadSchema = true
        LLMMockURLProtocol.requestHandler = { req in
            callCount += 1
            let body = try? JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            let gen = body?["generationConfig"] as? [String: Any]
            if callCount == 1 {
                // First attempt carries the schema → reject it.
                return (mockHTTPResponse(url: req.url!, statusCode: 400), Data("{\"error\":\"bad schema\"}".utf8))
            }
            secondHadSchema = gen?["responseSchema"] != nil
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "ok"))
        }
        let provider = GoogleProvider(apiKey: "k", model: "gemini-2.5-flash", session: session)
        let (name, schema) = StructuredOutputSchemas.schema(for: .jobExtraction)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "q")],
            model: "gemini-2.5-flash",
            responseFormat: .jsonSchema(name: name, schema: schema)
        )
        let resp = try await provider.complete(req)

        XCTAssertEqual(callCount, 2, "should retry exactly once after the 400")
        XCTAssertFalse(secondHadSchema, "the retry must drop responseSchema (plain JSON mode)")
        XCTAssertEqual(resp.content, "ok")
    }

    /// A 400 that is NOT from a responseSchema request must still surface as an error (no retry).
    func testJSONObject400_doesNotRetry() async {
        var callCount = 0
        LLMMockURLProtocol.requestHandler = { req in
            callCount += 1
            return (mockHTTPResponse(url: req.url!, statusCode: 400), Data("{\"error\":\"x\"}".utf8))
        }
        let provider = GoogleProvider(apiKey: "k", model: "gemini-2.5-flash", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "q")],
            model: "gemini-2.5-flash",
            responseFormat: .jsonObject
        )
        do {
            _ = try await provider.complete(req)
            XCTFail("expected httpError")
        } catch let LLMProviderError.httpError(code, _) {
            XCTAssertEqual(code, 400)
            XCTAssertEqual(callCount, 1, "no schema was sent, so there must be no fallback retry")
        } catch {
            XCTFail("expected httpError(400), got \(error)")
        }
    }
}

// MARK: - LMStudio provider tests

final class LMStudioProviderTests: LLMMockProviderTestCase {
    func testRequestURLUsesLocalhost() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), openAIResponse(content: "local"))
        }
        let provider = LMStudioProvider(
            baseURL: "http://127.0.0.1:1234",
            model: "gemma-4b",
            session: session
        )
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "extract")],
            model: "gemma-4b"
        )
        let result = try await provider.complete(req)

        XCTAssertEqual(
            LLMMockURLProtocol.capturedRequests.first?.url?.absoluteString,
            "http://127.0.0.1:1234/v1/chat/completions"
        )
        XCTAssertEqual(result.content, "local")
    }

    func testConcurrencyLimitIsOne() {
        XCTAssertEqual(LMStudioProvider().concurrencyLimit, 1)
    }

    func testNoAuthHeaderWhenNoAPIKey() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), openAIResponse(content: "ok"))
        }
        let provider = LMStudioProvider(apiKey: "", session: session)
        _ = try await provider.complete(
            ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "m")
        )
        XCTAssertNil(LLMMockURLProtocol.capturedRequests.first?.value(forHTTPHeaderField: "Authorization"))
    }
}

// MARK: - OpenRouter provider tests

final class OpenRouterProviderTests: LLMMockProviderTestCase {
    func testRequestURLAndExtraHeaders() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), openAIResponse(content: "ok"))
        }
        let provider = OpenRouterProvider(apiKey: "or-key", session: session)
        _ = try await provider.complete(
            ChatRequest(messages: [ChatMessage(role: "user", content: "go")], model: "openai/gpt-4o")
        )
        let captured = try XCTUnwrap(LLMMockURLProtocol.capturedRequests.first)
        XCTAssertEqual(captured.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertNotNil(captured.value(forHTTPHeaderField: "HTTP-Referer"))
        XCTAssertNotNil(captured.value(forHTTPHeaderField: "X-Title"))
    }

    func testConcurrencyLimit() {
        XCTAssertEqual(OpenRouterProvider(apiKey: "").concurrencyLimit, 3)
    }
}

// MARK: - Custom provider tests

final class CustomProviderTests: LLMMockProviderTestCase {
    func testRequestURLUsesCustomBaseURL() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), openAIResponse(content: "custom"))
        }
        let provider = CustomProvider(
            baseURL: "https://my-llm.example.com",
            model: "my-model",
            session: session
        )
        _ = try await provider.complete(
            ChatRequest(messages: [ChatMessage(role: "user", content: "q")], model: "my-model")
        )
        XCTAssertEqual(
            LLMMockURLProtocol.capturedRequests.first?.url?.absoluteString,
            "https://my-llm.example.com/v1/chat/completions"
        )
    }

    func testConcurrencyLimit() {
        XCTAssertEqual(CustomProvider(baseURL: "http://x", model: "m").concurrencyLimit, 2)
    }
}

// MARK: - LLMProviderFactory tests

final class LLMProviderFactoryTests: XCTestCase {
    func testResolveBaseURLOpenAI() {
        XCTAssertEqual(
            LLMProviderFactory.resolveBaseURL(provider: "openai", customBaseURL: ""),
            "https://api.openai.com"
        )
    }

    func testResolveBaseURLOpenRouter() {
        XCTAssertEqual(
            LLMProviderFactory.resolveBaseURL(provider: "openrouter", customBaseURL: ""),
            "https://openrouter.ai/api"
        )
    }

    func testResolveBaseURLAnthropic() {
        XCTAssertEqual(
            LLMProviderFactory.resolveBaseURL(provider: "anthropic", customBaseURL: ""),
            "https://api.anthropic.com"
        )
    }

    func testResolveBaseURLGoogle() {
        XCTAssertEqual(
            LLMProviderFactory.resolveBaseURL(provider: "google", customBaseURL: ""),
            "https://generativelanguage.googleapis.com"
        )
    }

    func testResolveBaseURLCustom() {
        XCTAssertEqual(
            LLMProviderFactory.resolveBaseURL(provider: "custom", customBaseURL: "http://myserver.local"),
            "http://myserver.local"
        )
    }

    func testResolveBaseURLDefault() {
        XCTAssertEqual(
            LLMProviderFactory.resolveBaseURL(provider: "lmstudio", customBaseURL: ""),
            "http://127.0.0.1:1234"
        )
    }

    func testTrailingSlashStripped() {
        XCTAssertEqual(
            LLMProviderFactory.resolveBaseURL(provider: "custom", customBaseURL: "http://x.com/"),
            "http://x.com"
        )
    }
}

// MARK: - HTTP error tests

final class LLMProviderErrorTests: LLMMockProviderTestCase {
    func testHTTP500ThrowsError() async {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!, statusCode: 500), Data("Internal error".utf8))
        }
        let provider = OpenAIProvider(apiKey: "k", session: session)
        do {
            _ = try await provider.complete(
                ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "m")
            )
            XCTFail("Should have thrown")
        } catch let err as LLMProviderError {
            if case let .httpError(code, _) = err {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Wrong error type: \(err)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// TASK-127 regression: persisted error descriptions must not include raw provider response bodies.
    func testHTTPErrorDescriptionOmitsResponseBody() {
        let sensitiveBody = "Bearer token: sk-secret123, user data: john@example.com"
        let err = LLMProviderError.httpError(statusCode: 429, body: sensitiveBody)
        let description = err.localizedDescription
        XCTAssertFalse(description.contains(sensitiveBody), "localizedDescription must not include raw response body")
        XCTAssertFalse(description.contains("Bearer"), "localizedDescription must not include auth tokens from body")
        XCTAssertTrue(description.contains("429"), "localizedDescription must include the status code")
    }

    func testDecodeErrorDescriptionOmitsRawContent() {
        let err = LLMProviderError.noResponse
        let description = err.localizedDescription
        XCTAssertFalse(description.isEmpty)
    }

    /// TASK-542: 401/403 must produce an actionable "check your API key" message (not a bare code),
    /// while other codes keep the terse form. The raw body must still never leak.
    func testAuthErrorDescriptionsAreActionable() {
        for code in [401, 403] {
            let description = LLMProviderError.httpError(statusCode: code, body: "secret-body").localizedDescription
            XCTAssertTrue(description.localizedCaseInsensitiveContains("key"), "HTTP \(code) should mention the key")
            XCTAssertTrue(description.contains("\(code)"), "HTTP \(code) should include the code")
            XCTAssertFalse(description.contains("secret-body"), "must not leak the response body")
        }
        XCTAssertEqual(LLMProviderError.httpError(statusCode: 500, body: "x").localizedDescription, "LLM HTTP 500")
    }
}

// MARK: - TASK-320/321/322 factory tests

final class LLMProviderFactoryMakeProviderTests: XCTestCase {
    private func makeSettings(provider: String, model: String = "test-model") throws -> SettingsStore {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        settings.llmProvider = provider
        settings.llmModel = model
        return settings
    }

    // TASK-321: factory builds a provider whose id is the provider type, not the model string
    func testProviderFactoryUsesConfiguredModel() throws {
        let settings = try makeSettings(provider: "openai", model: "gpt-4o")
        let provider = LLMProviderFactory.makeProvider(settings: settings)
        // Provider id is the provider type ("openai"), not the model name
        XCTAssertEqual(provider.id, "openai")
        XCTAssertNotEqual(provider.id, "gpt-4o")
    }

    // TASK-321: model passed to ChatRequest is the source of truth (provider id != model name)
    func testProviderIDIsNotTheModelName() throws {
        let settings = try makeSettings(provider: "anthropic", model: "claude-opus-4-5")
        let provider = LLMProviderFactory.makeProvider(settings: settings)
        XCTAssertEqual(provider.id, "anthropic")
        XCTAssertNotEqual(provider.id, settings.llmModel)
    }
}

// MARK: - TASK-323: Google responseFormat tests

extension GoogleProviderTests {
    func testNilResponseFormat_doesNotSetGenerationConfig() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let body = try JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            XCTAssertNil(body?["generationConfig"], "generationConfig should not be set for nil responseFormat")
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "ok"))
        }
        let provider = GoogleProvider(apiKey: "k", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "ping")],
            model: "gemini-2.5-flash",
            responseFormat: nil
        )
        _ = try await provider.complete(req)
    }

    func testTextResponseFormat_doesNotSetGenerationConfig() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let body = try JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            XCTAssertNil(body?["generationConfig"], "generationConfig should not be set for .text responseFormat")
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "ok"))
        }
        let provider = GoogleProvider(apiKey: "k", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "ping")],
            model: "gemini-2.5-flash",
            responseFormat: .text
        )
        _ = try await provider.complete(req)
    }

    func testJsonObjectResponseFormat_setsResponseMimeType() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let body = try JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            let genConfig = body?["generationConfig"] as? [String: Any]
            XCTAssertEqual(genConfig?["responseMimeType"] as? String, "application/json")
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "{}"))
        }
        let provider = GoogleProvider(apiKey: "k", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "extract")],
            model: "gemini-2.5-flash",
            responseFormat: .jsonObject
        )
        _ = try await provider.complete(req)
    }

    func testJsonSchemaResponseFormat_setsResponseMimeType() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let body = try JSONSerialization.jsonObject(with: requestBody(req) ?? Data()) as? [String: Any]
            let genConfig = body?["generationConfig"] as? [String: Any]
            XCTAssertEqual(genConfig?["responseMimeType"] as? String, "application/json")
            return (mockHTTPResponse(url: req.url!), self.googleResponse(text: "{}"))
        }
        let provider = GoogleProvider(apiKey: "k", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "extract")],
            model: "gemini-2.5-flash",
            responseFormat: .jsonSchema(name: "job", schema: "{\"type\":\"object\"}")
        )
        _ = try await provider.complete(req)
    }
}

// MARK: - TASK-324: Timeout normalization tests

final class TimeoutNormalizationTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        LLMMockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }
        session = makeMockSession()
    }

    func testOpenAITransport_timeoutMapsToProviderError() async {
        let provider = OpenAIProvider(apiKey: "sk-test", timeoutSeconds: 30, session: session)
        do {
            _ = try await provider.complete(
                ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "gpt-4o")
            )
            XCTFail("Expected timeout error")
        } catch let err as LLMProviderError {
            if case let .timeout(seconds) = err {
                XCTAssertEqual(seconds, 30)
            } else {
                XCTFail("Wrong error type: \(err)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGoogleProvider_timeoutMapsToProviderError() async {
        let provider = GoogleProvider(apiKey: "gkey", timeoutSeconds: 45, session: session)
        do {
            _ = try await provider.complete(
                ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "gemini-2.5-flash")
            )
            XCTFail("Expected timeout error")
        } catch let err as LLMProviderError {
            if case let .timeout(seconds) = err {
                XCTAssertEqual(seconds, 45)
            } else {
                XCTFail("Wrong error type: \(err)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAnthropicProvider_timeoutMapsToProviderError() async {
        let provider = AnthropicProvider(apiKey: "ant-key", timeoutSeconds: 60, session: session)
        do {
            _ = try await provider.complete(
                ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "claude-sonnet-4-6")
            )
            XCTFail("Expected timeout error")
        } catch let err as LLMProviderError {
            if case let .timeout(seconds) = err {
                XCTAssertEqual(seconds, 60)
            } else {
                XCTFail("Wrong error type: \(err)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - TASK-326: OpenAI 400 format-error narrowing tests

final class OpenAI400NarrowingTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        session = makeMockSession()
    }

    func testFormatError400_retriesWithLowerFormat() async throws {
        var callCount = 0
        LLMMockURLProtocol.requestHandler = { req in
            callCount += 1
            if callCount == 1 {
                let body = Data("""
                {"error": {"message": "response_format type 'json_schema' is not supported"}}
                """.utf8)
                return (mockHTTPResponse(url: req.url!, statusCode: 400), body)
            }
            return (mockHTTPResponse(url: req.url!), openAIResponse(content: "{}"))
        }
        let provider = OpenAIProvider(apiKey: "sk-test", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "extract")],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "job", schema: "{\"type\":\"object\"}")
        )
        let result = try await provider.complete(req)
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(result.responseFormat, .jsonObject)
    }

    func testUnrelated400_throwsImmediatelyWithoutRetry() async {
        var callCount = 0
        LLMMockURLProtocol.requestHandler = { req in
            callCount += 1
            let body = Data("Invalid API key".utf8)
            return (mockHTTPResponse(url: req.url!, statusCode: 400), body)
        }
        let provider = OpenAIProvider(apiKey: "sk-bad", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "job", schema: "{\"type\":\"object\"}")
        )
        do {
            _ = try await provider.complete(req)
            XCTFail("Expected httpError")
        } catch let err as LLMProviderError {
            if case let .httpError(code, body) = err {
                XCTAssertEqual(code, 400)
                XCTAssertEqual(body, "Invalid API key")
            } else {
                XCTFail("Wrong error: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(callCount, 1, "Should not retry on unrelated 400")
    }
}

// swiftlint:enable force_unwrapping file_length
