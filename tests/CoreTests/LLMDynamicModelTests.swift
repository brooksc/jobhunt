// swiftlint:disable force_unwrapping optional_data_string_conversion
import XCTest
@testable import JobhuntCore

// Tests for dynamic model loading (ModelCatalog), the explicit-model-selection guard, and the
// Anthropic structured-output path. Reuses LLMMockURLProtocol / LLMMockProviderTestCase from
// LLMProviderTests.swift (same test target).

private func http(_ url: URL, _ code: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
}

private func bodyText(_ request: URLRequest) -> String {
    if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
    if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        var read = 0
        repeat {
            read = stream.read(buffer, maxLength: 4096)
            if read > 0 { data.append(buffer, count: read) }
        } while read > 0
        return String(decoding: data, as: UTF8.self)
    }
    return ""
}

// MARK: - ModelCatalog

final class ModelCatalogTests: LLMMockProviderTestCase {
    func testOpenAIStyle_parsesAndSortsIDs() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (http(req.url!), Data(#"{"data":[{"id":"zeta"},{"id":"alpha"}]}"#.utf8))
        }
        let models = try await ModelCatalog.listModels(
            provider: "lmstudio", baseURL: "http://127.0.0.1:1234", apiKey: "", session: session
        )
        XCTAssertEqual(models, ["alpha", "zeta"])
        XCTAssertTrue(LLMMockURLProtocol.capturedRequests.first?.url?.absoluteString
            .hasSuffix("/v1/models") ?? false)
    }

    func testAnthropic_sendsKeyAndVersionHeaders() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            (http(req.url!), Data(#"{"data":[{"id":"claude-opus-4-8"}]}"#.utf8))
        }
        let models = try await ModelCatalog.listModels(
            provider: "anthropic", baseURL: "", apiKey: "ant-key", session: session
        )
        XCTAssertEqual(models, ["claude-opus-4-8"])
        let req = LLMMockURLProtocol.capturedRequests.first
        XCTAssertEqual(req?.url?.host, "api.anthropic.com")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "x-api-key"), "ant-key")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testAnthropic_missingKey_throwsBeforeRequest() async {
        do {
            _ = try await ModelCatalog.listModels(
                provider: "anthropic", baseURL: "", apiKey: "", session: session
            )
            XCTFail("expected missingAPIKey")
        } catch let ModelCatalogError.missingAPIKey(provider) {
            XCTAssertEqual(provider, "anthropic")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(LLMMockURLProtocol.capturedRequests.isEmpty)
    }

    func testGoogle_filtersGenerateContentAndStripsModelsPrefix() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let json = """
            {"models":[
              {"name":"models/gemini-pro","supportedGenerationMethods":["generateContent"]},
              {"name":"models/text-embed","supportedGenerationMethods":["embedContent"]}
            ]}
            """
            return (http(req.url!), Data(json.utf8))
        }
        let models = try await ModelCatalog.listModels(
            provider: "google", baseURL: "", apiKey: "gkey", session: session
        )
        XCTAssertEqual(models, ["gemini-pro"])
        XCTAssertEqual(
            LLMMockURLProtocol.capturedRequests.first?
                .value(forHTTPHeaderField: "x-goog-api-key"),
            "gkey"
        )
    }

    func testHTTPError_throws() async {
        LLMMockURLProtocol.requestHandler = { req in (http(req.url!, 500), Data("nope".utf8)) }
        do {
            _ = try await ModelCatalog.listModels(
                provider: "lmstudio", baseURL: "http://127.0.0.1:1234", apiKey: "", session: session
            )
            XCTFail("expected httpError")
        } catch let ModelCatalogError.httpError(code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

// MARK: - Anthropic structured output

final class AnthropicStructuredOutputTests: LLMMockProviderTestCase {
    func testStructuredOutput_sendsOutputConfigJSONSchema() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            let json = #"{"model":"claude-x","content":[{"text":"{\"title\":\"T\"}"}],"#
                + #""usage":{"input_tokens":1,"output_tokens":1}}"#
            return (http(req.url!), Data(json.utf8))
        }
        let provider = AnthropicProvider(apiKey: "k", session: session)
        let request = ChatRequest(
            messages: [ChatMessage(role: "user", content: "extract")],
            model: "claude-opus-4-8",
            responseFormat: .jsonObject,
            structuredOutput: .jobExtraction
        )
        let response = try await provider.complete(request)
        XCTAssertEqual(response.content, "{\"title\":\"T\"}")
        // TASK-565: a successful structured-output call records json_schema, not json_object.
        let expected = StructuredOutputSchemas.schema(for: .jobExtraction)
        XCTAssertEqual(response.responseFormat, .jsonSchema(name: expected.name, schema: expected.schema))

        let sent = try bodyText(XCTUnwrap(LLMMockURLProtocol.capturedRequests.first))
        XCTAssertTrue(sent.contains("output_config"), "should send output_config")
        XCTAssertTrue(sent.contains("json_schema"), "should send json_schema format")
    }

    func testStructuredOutput_400FormatError_retriesWithoutOutputConfig() async throws {
        LLMMockURLProtocol.requestHandler = { req in
            if bodyText(req).contains("output_config") {
                return (http(req.url!, 400), Data(#"{"error":"output_config not supported"}"#.utf8))
            }
            let json = #"{"model":"claude-old","content":[{"text":"{\"title\":\"R\"}"}]}"#
            return (http(req.url!), Data(json.utf8))
        }
        let provider = AnthropicProvider(apiKey: "k", session: session)
        let request = ChatRequest(
            messages: [ChatMessage(role: "user", content: "extract")],
            model: "claude-3-old",
            structuredOutput: .jobExtraction
        )
        let response = try await provider.complete(request)
        XCTAssertEqual(response.content, "{\"title\":\"R\"}")
        XCTAssertEqual(response.responseFormat, .text, "fallback path returns free-form text")
        XCTAssertEqual(LLMMockURLProtocol.capturedRequests.count, 2, "should retry once")
        XCTAssertFalse(bodyText(LLMMockURLProtocol.capturedRequests[1]).contains("output_config"))
    }
}

// MARK: - Explicit model-selection guard

private struct StubProvider: LLMProvider {
    let id: String
    let content: String
    var concurrencyLimit: Int {
        1
    }

    func complete(_: ChatRequest) async throws -> ChatResponse {
        ChatResponse(content: content, model: "stub", responseFormat: .jsonObject)
    }
}

final class ModelSelectionGuardTests: XCTestCase {
    private func snapshot() -> JobExtractionSnapshot {
        JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Job",
            captureCleanedDescription: "We are hiring a Swift engineer with five years of experience.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )
    }

    private func settings(model: String, provider: String) -> ExtractionSettings {
        ExtractionSettings(
            llmModel: model, llmProvider: provider, preferredLocations: "",
            locationFilterEnabled: false, locationAllowRemote: true,
            locationAllowHybrid: true, locationAllowOnsite: true
        )
    }

    func testExtract_emptyModel_nonApple_throws() async {
        let provider = StubProvider(id: "lmstudio", content: "{}")
        do {
            _ = try await ExtractionEngine.extract(
                snapshot: snapshot(), provider: provider,
                settings: settings(model: "", provider: "lmstudio")
            )
            XCTFail("expected noModelSelected")
        } catch ExtractionEngineError.noModelSelected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testScoreFit_emptyModel_throws() async {
        let provider = StubProvider(id: "openai", content: "{}")
        let job = JobFitSnapshot(
            title: "T", company: "C", seniority: nil, extractedJSON: nil, extractionModel: nil
        )
        do {
            _ = try await ExtractionEngine.scoreFit(
                job: job, resume: ResumeSnapshot(text: "my resume"), model: "", provider: provider,
                feedback: []
            )
            XCTFail("expected noModelSelected")
        } catch ExtractionEngineError.noModelSelected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

// swiftlint:enable force_unwrapping optional_data_string_conversion
