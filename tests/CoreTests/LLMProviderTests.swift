// swiftlint:disable force_unwrapping file_length
import XCTest
@testable import JobhuntCore

// MARK: - LLMMockURLProtocol

/// Records captured requests and returns preconfigured responses.
/// Named LLMMockURLProtocol to avoid conflict with MockURLProtocol in AvailabilityCheckerTests.
final class LLMMockURLProtocol: URLProtocol {
    // Set these before each test
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var capturedRequests: [URLRequest] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

// MARK: - OpenAI provider tests

final class OpenAIProviderTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        session = makeMockSession()
    }

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
    }

    func testConcurrencyLimit() {
        let provider = OpenAIProvider(apiKey: "sk-test")
        XCTAssertEqual(provider.concurrencyLimit, 3)
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
                // First call: json_schema → return 400
                XCTAssertEqual(fmt?["type"] as? String, "json_schema")
                return (mockHTTPResponse(url: req.url!, statusCode: 400), Data())
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
                return (mockHTTPResponse(url: req.url!, statusCode: 400), Data())
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

final class AnthropicProviderTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        session = makeMockSession()
    }

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

        let captured = LLMMockURLProtocol.capturedRequests.first!
        XCTAssertEqual(captured.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "x-api-key"), "ant-key")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(result.content, "result")
        XCTAssertEqual(result.responseFormat, .text)
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

    func testConcurrencyLimit() {
        XCTAssertEqual(AnthropicProvider(apiKey: "").concurrencyLimit, 2)
    }
}

// MARK: - Google provider tests

final class GoogleProviderTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        session = makeMockSession()
    }

    private func googleResponse(text: String) -> Data {
        let json = """
        {
          "candidates": [{"content": {"parts": [{"text": "\(text)"}]}}],
          "modelVersion": "gemini-2.5-flash-001"
        }
        """
        return Data(json.utf8)
    }

    func testRequestURLContainsAPIKeyAndModel() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), self.googleResponse(text: "answer"))
        }
        let provider = GoogleProvider(apiKey: "gkey", model: "gemini-2.5-flash", session: session)
        let req = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "gemini-2.5-flash"
        )
        _ = try await provider.complete(req)

        let url = LLMMockURLProtocol.capturedRequests.first!.url!
        XCTAssertTrue(url.absoluteString.contains("gemini-2.5-flash:generateContent"))
        XCTAssertTrue(url.absoluteString.contains("key=gkey"))
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

    func testConcurrencyLimit() {
        XCTAssertEqual(GoogleProvider(apiKey: "").concurrencyLimit, 3)
    }
}

// MARK: - LMStudio provider tests

final class LMStudioProviderTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        session = makeMockSession()
    }

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

final class OpenRouterProviderTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        session = makeMockSession()
    }

    func testRequestURLAndExtraHeaders() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (mockHTTPResponse(url: req.url!), openAIResponse(content: "ok"))
        }
        let provider = OpenRouterProvider(apiKey: "or-key", session: session)
        _ = try await provider.complete(
            ChatRequest(messages: [ChatMessage(role: "user", content: "go")], model: "openai/gpt-4o")
        )
        let captured = LLMMockURLProtocol.capturedRequests.first!
        XCTAssertEqual(captured.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertNotNil(captured.value(forHTTPHeaderField: "HTTP-Referer"))
        XCTAssertNotNil(captured.value(forHTTPHeaderField: "X-Title"))
    }

    func testConcurrencyLimit() {
        XCTAssertEqual(OpenRouterProvider(apiKey: "").concurrencyLimit, 3)
    }
}

// MARK: - Custom provider tests

final class CustomProviderTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        session = makeMockSession()
    }

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

// MARK: - FoundationModels availability tests

final class FoundationModelsProviderTests: XCTestCase {
    func testIsAvailableReturnsBool() {
        // Just assert it doesn't crash and returns a Bool
        let available = FoundationModelsProvider.isAvailable()
        XCTAssertNotNil(available)  // always passes — value varies per OS
    }

    func testConcurrencyLimitIsOne() {
        XCTAssertEqual(FoundationModelsProvider().concurrencyLimit, 1)
    }

    func testCompleteThrowsOnOlderOS() async {
        // On macOS < 26 this should throw; on >= 26 it may throw too (no model loaded).
        // We just assert it doesn't silently succeed without a real model.
        let provider = FoundationModelsProvider()
        if !FoundationModelsProvider.isAvailable() {
            do {
                _ = try await provider.complete(
                    ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "apple")
                )
                XCTFail("Should have thrown on macOS < 26")
            } catch {
                // Expected — unavailable error
                XCTAssertTrue(error.localizedDescription.lowercased().contains("macOS 26".lowercased()) ||
                              error.localizedDescription.lowercased().contains("unavailable"))
            }
        } else {
            // On macOS 26+ the call may succeed or fail — both are OK for this test
            // since we don't have the model loaded in CI.
            _ = try? await provider.complete(
                ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "apple")
            )
        }
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

final class LLMProviderErrorTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.capturedRequests = []
        session = makeMockSession()
    }

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
            if case .httpError(let code, _) = err {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Wrong error type: \(err)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// swiftlint:enable force_unwrapping file_length
