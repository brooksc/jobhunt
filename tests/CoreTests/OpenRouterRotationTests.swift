import XCTest
@testable import JobhuntCore

/// Local mock helpers (the ones in LLMProviderTests.swift are file-private). LLMMockURLProtocol is
/// module-internal and shared.
private func orMakeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LLMMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func orRequestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

private func orOpenAIResponse(content: String) -> Data {
    Data("{\"model\":\"m\",\"choices\":[{\"message\":{\"content\":\(jsonString(content))}}]}".utf8)
}

private func jsonString(_ s: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: [s])
    let arr = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
    return String(arr.dropFirst().dropLast()) // strip [ ]
}

private func orHTTPResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

/// TASK-462: OpenRouter free-model rotation pool + provider failover.
final class OpenRouterRotationTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        LLMMockURLProtocol.reset()
        session = orMakeMockSession()
    }

    override func tearDown() {
        LLMMockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    private func modelsFixture() throws -> Data {
        // repo root: tests/CoreTests/OpenRouterRotationTests.swift → ../../../
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("tests/fixtures/openrouter-models.json"))
    }

    // MARK: - AC#2: free-structured filter against the captured fixture

    func testFilterFreeStructuredAgainstFixture() throws {
        let response = try JSONDecoder().decode(OpenRouterModelPool.ModelsResponse.self, from: modelsFixture())
        let free = OpenRouterModelPool.filterFreeStructured(response.data)
        // Only the two free + structured-output + text-capable models; paid, non-structured, and
        // image-only are excluded.
        XCTAssertEqual(free, ["meta-llama/llama-3.1-8b-instruct:free", "google/gemini-flash-1.5-8b:free"])
    }

    // MARK: - Pool fetch + TTL cache + round-robin

    func testPoolFetchesFiltersAndCachesWithinTTL() async throws {
        let fixture = try modelsFixture()
        var modelsCalls = 0
        LLMMockURLProtocol.requestHandler = { req in
            if req.url?.path.contains("/models") == true {
                modelsCalls += 1
                return (orHTTPResponse(url: req.url!), fixture)
            }
            return (orHTTPResponse(url: req.url!), Data())
        }

        let pool = OpenRouterModelPool(ttl: 3600)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = await pool.models(apiKey: "k", session: session, now: now)
        XCTAssertEqual(first.count, 2)
        // Within TTL → served from cache, no refetch.
        _ = await pool.models(apiKey: "k", session: session, now: now.addingTimeInterval(60))
        XCTAssertEqual(modelsCalls, 1, "second call within TTL must not refetch")
        // After TTL → refetch.
        _ = await pool.models(apiKey: "k", session: session, now: now.addingTimeInterval(4000))
        XCTAssertEqual(modelsCalls, 2, "call after TTL must refetch")
    }

    func testNextModelsRoundRobinAdvances() async throws {
        let fixture = try modelsFixture()
        LLMMockURLProtocol.requestHandler = { req in (orHTTPResponse(url: req.url!), fixture) }
        let pool = OpenRouterModelPool()
        let a = await pool.nextModels(count: 1, apiKey: "k", session: session)
        let b = await pool.nextModels(count: 1, apiKey: "k", session: session)
        let c = await pool.nextModels(count: 1, apiKey: "k", session: session)
        XCTAssertEqual(a, ["meta-llama/llama-3.1-8b-instruct:free"])
        XCTAssertEqual(b, ["google/gemini-flash-1.5-8b:free"])
        XCTAssertEqual(c, ["meta-llama/llama-3.1-8b-instruct:free"], "index wraps around")
    }

    // MARK: - AC#3/#4: provider rotation + failover

    private func chatModel(_ req: URLRequest) -> String? {
        guard let body = orRequestBody(req),
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return obj["model"] as? String
    }

    func testRotationFailsOverToNextModelOnError() async throws {
        let fixture = try modelsFixture()
        var chatModels: [String] = []
        LLMMockURLProtocol.requestHandler = { [self] req in
            if req.url?.path.contains("/models") == true {
                return (orHTTPResponse(url: req.url!), fixture)
            }
            // chat/completions: first model errors, second succeeds.
            let model = chatModel(req) ?? ""
            chatModels.append(model)
            if model == "meta-llama/llama-3.1-8b-instruct:free" {
                return (orHTTPResponse(url: req.url!, statusCode: 500), Data("{\"error\":\"boom\"}".utf8))
            }
            return (orHTTPResponse(url: req.url!), orOpenAIResponse(content: "{}"))
        }

        let provider = OpenRouterProvider(apiKey: "k", model: "ignored", session: session, pool: OpenRouterModelPool())
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "ignored")
        let result = try await provider.complete(req)

        XCTAssertEqual(result.content, "{}")
        XCTAssertEqual(
            chatModels,
            ["meta-llama/llama-3.1-8b-instruct:free", "google/gemini-flash-1.5-8b:free"],
            "failover tried the first model, then the second"
        )
    }

    func testRotationExhaustedThrowsOnce() async throws {
        let fixture = try modelsFixture()
        var chatAttempts = 0
        LLMMockURLProtocol.requestHandler = { req in
            if req.url?.path.contains("/models") == true {
                return (orHTTPResponse(url: req.url!), fixture)
            }
            chatAttempts += 1
            return (orHTTPResponse(url: req.url!, statusCode: 500), Data("{\"error\":\"down\"}".utf8))
        }

        let provider = OpenRouterProvider(apiKey: "k", model: "ignored", session: session, pool: OpenRouterModelPool())
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "ignored")
        do {
            _ = try await provider.complete(req)
            XCTFail("expected throw after exhausting all rotation candidates")
        } catch {
            // expected — exactly one error surfaces to the caller (queue counts one failure).
        }
        XCTAssertEqual(chatAttempts, 2, "tried both free models before throwing once")
    }

    func testRotationDisabled_usesConfiguredModel() async throws {
        var chatModels: [String] = []
        LLMMockURLProtocol.requestHandler = { [self] req in
            chatModels.append(chatModel(req) ?? "")
            return (orHTTPResponse(url: req.url!), orOpenAIResponse(content: "ok"))
        }
        // pool: nil → rotation off.
        let provider = OpenRouterProvider(apiKey: "k", model: "configured-model", session: session, pool: nil)
        let req = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "configured-model")
        _ = try await provider.complete(req)
        XCTAssertEqual(chatModels, ["configured-model"], "rotation off must use the single configured model")
    }
}
