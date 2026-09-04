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
        // Nudge Settings open with the app-owned sidebar row first, so this doesn't depend on global
        // keyboard focus while the mock-backed queue starts processing in the background. If the row
        // doesn't get there, selectSettingsTab's ⌘, retry loop does.
        let settingsRow = app.descendants(matching: .any).matching(identifier: "sidebar.settings").firstMatch
        if settingsRow.waitForExistence(timeout: 5) {
            settingsRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            _ = waitUntil(timeout: 5) { self.app.windows[settingsWindowIdentifier].exists }
        }

        // TASK-716: the tab is a toolbar button whose name lives in `title`, not `label`. The old
        // label predicate here matched nothing, which is why this test failed one step before the
        // Test Connection click. selectSettingsTab owns that query for every AppUITests class.
        let settingsWindow = selectSettingsTab(app, "AI")

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
