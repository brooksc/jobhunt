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
        // Settings is the standard macOS ⌘, preferences window now, not an in-window section.
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 5),
                      "⌘, should open the Settings window")

        // The Settings sub-tabs are a TabView; match the "AI" tab item (provider/model/pricing) by
        // label regardless of the concrete element type the macOS tab bar exposes.
        let llmTab = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'AI'")).firstMatch
        XCTAssertTrue(llmTab.waitForExistence(timeout: 10), "AI settings tab must exist")
        llmTab.click()

        let testButton = app.buttons["Test Connection"].firstMatch
        XCTAssertTrue(testButton.waitForExistence(timeout: 5), "Test Connection button must exist")
        testButton.click()

        // The app launched with provider=lmstudio pointed at the mock, so the connection must succeed.
        let success = app.descendants(matching: .any)
            .matching(identifier: "llm.connection.success").firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 15),
                      "Test Connection should succeed against the localhost mock LLM server")
    }
}
