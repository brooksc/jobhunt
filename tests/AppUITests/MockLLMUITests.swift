import XCTest

/// End-to-end UI coverage of the AI wiring: launch the app pointed at a localhost mock OpenAI server
/// (hosted by this test runner via `--llm-mock-port`) and confirm the LLM settings "Test Connection"
/// succeeds against it — exercising the app's real provider config → HTTP → parse path with no key.
final class MockLLMUITests: XCTestCase {
    private var server: MockLLMServer!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = try MockLLMServer()
        try server.start()
        app = launchApp(llmMockPort: Int(server.port))
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        server?.stop()
        server = nil
        super.tearDown()
    }

    func testLLMTestConnection_succeedsAgainstMockServer() {
        // Use the app-owned Settings row so this test does not depend on global keyboard focus while
        // the mock-backed queue starts processing in the background.
        let settingsRow = app.descendants(matching: .any).matching(identifier: "sidebar.settings").firstMatch
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 5), "the Settings sidebar row must exist")
        settingsRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count > 1 }, "the Settings window should open")
        guard let settingsWindow = app.windows.allElementsBoundByIndex.first(where: { $0.identifier != "main" }) else {
            return XCTFail("the Settings window should be present in the accessibility hierarchy")
        }
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5), "the Settings window should remain available")

        // TabView's accessibility role varies by macOS release, so identify the tab by its label.
        let aiTab = settingsWindow.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] %@", "AI"))
            .firstMatch
        XCTAssertTrue(aiTab.waitForExistence(timeout: 5), "the AI settings tab must exist")
        aiTab.click()

        let testButton = settingsWindow.buttons["Test Connection"].firstMatch
        XCTAssertTrue(testButton.waitForExistence(timeout: 5), "Test Connection button must exist")
        testButton.click()

        // The app launched with provider=lmstudio pointed at the mock, so the connection must succeed.
        let success = settingsWindow.descendants(matching: .any)
            .matching(identifier: "llm.connection.success").firstMatch
        guard success.waitForExistence(timeout: 15) else {
            let failure = settingsWindow.descendants(matching: .any)
                .matching(identifier: "llm.connection.failure").firstMatch
            let detail = failure.exists ? "the app reported a connection failure" : "no connection result appeared"
            return XCTFail("Test Connection should succeed against the localhost mock LLM server: \(detail)")
        }
    }
}
