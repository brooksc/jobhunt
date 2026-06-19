import XCTest

/// Unit tests for the pure mock-response logic (no networking).
final class MockLLMResponderTests: XCTestCase {
    private func body(schemaName: String?, messages: [(String, String)] = []) -> Data {
        var obj: [String: Any] = [
            "model": "mock-model",
            "messages": messages.map { ["role": $0.0, "content": $0.1] }
        ]
        if let schemaName {
            obj["response_format"] = ["type": "json_schema", "json_schema": ["name": schemaName]]
        }
        return try! JSONSerialization.data(withJSONObject: obj) // swiftlint:disable:this force_try
    }

    // MARK: - Classification

    func testClassify_bySchemaName() {
        XCTAssertEqual(
            MockLLMResponder.classify(body: ["response_format": ["json_schema": ["name": "fit_score"]]]),
            .fit
        )
        XCTAssertEqual(
            MockLLMResponder.classify(body: ["response_format": ["json_schema": ["name": "job_extraction"]]]),
            .extraction
        )
    }

    func testClassify_fallbackByResumeKeyword() {
        // No schema name (format downgraded) — the fit prompt is the only one mentioning a resume.
        XCTAssertEqual(
            MockLLMResponder.classify(body: ["messages": [[
                "role": "user",
                "content": "Score this resume against the job"
            ]]]),
            .fit
        )
        XCTAssertEqual(
            MockLLMResponder.classify(body: ["messages": [[
                "role": "user",
                "content": "Extract fields from this posting"
            ]]]),
            .extraction
        )
    }

    // MARK: - Input-aware title

    func testPageTitleRecoveredFromPrompt() {
        let data = body(
            schemaName: "job_extraction",
            messages: [(
                "user",
                "URL: https://x\nPage title: Senior iOS Engineer - Acme\nDescription: ..."
            )]
        )
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        XCTAssertEqual(MockLLMResponder.pageTitle(in: parsed), "Senior iOS Engineer - Acme")
    }

    func testTitleAndCompanySplit() {
        XCTAssertEqual(
            MockLLMResponder.titleAndCompany(from: "Senior iOS Engineer - Acme").title,
            "Senior iOS Engineer"
        )
        XCTAssertEqual(MockLLMResponder.titleAndCompany(from: "Senior iOS Engineer - Acme").company, "Acme")
        XCTAssertEqual(MockLLMResponder.titleAndCompany(from: "Staff Engineer @ Globex").company, "Globex")
        // No separator → title kept, placeholder company.
        XCTAssertEqual(MockLLMResponder.titleAndCompany(from: "Plain Title").title, "Plain Title")
        XCTAssertEqual(MockLLMResponder.titleAndCompany(from: "Plain Title").company, "MockCorp")
        // Empty → placeholders.
        XCTAssertEqual(MockLLMResponder.titleAndCompany(from: nil).company, "MockCorp")
    }

    // MARK: - Payload validity

    func testExtractionContentIsValidAndEchoesTitle() throws {
        let json = MockLLMResponder.extractionContentJSON(pageTitle: "Senior iOS Engineer - Acme")
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["title"] as? String, "Senior iOS Engineer")
        XCTAssertEqual(obj["company"] as? String, "Acme")
        XCTAssertNotNil(obj["skills"] as? [String])
        // Nullable scalars serialize as JSON null.
        XCTAssertTrue(obj["salary_note"] is NSNull)
    }

    func testFitContentHasTheFiveRequiredDimensions() throws {
        let json = MockLLMResponder.fitContentJSON()
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let dims = try XCTUnwrap(obj["dimensions"] as? [[String: Any]])
        let names = Set(dims.compactMap { $0["name"] as? String })
        XCTAssertEqual(
            names,
            ["required_qualifications", "preferred_qualifications", "skills", "experience_level", "domain_fit"]
        )
    }

    func testChatCompletionEnvelopeWrapsStructuredContent() throws {
        let response = MockLLMResponder.chatCompletion(requestBody: body(
            schemaName: "job_extraction",
            messages: [(
                "user",
                "Page title: Engineer - Acme\n"
            )]
        ))
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let choices = try XCTUnwrap(envelope["choices"] as? [[String: Any]])
        let content = try XCTUnwrap((choices.first?["message"] as? [String: Any])?["content"] as? String)
        // The message content is itself the structured extraction JSON.
        let inner = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        XCTAssertEqual(inner["company"] as? String, "Acme")
    }
}
