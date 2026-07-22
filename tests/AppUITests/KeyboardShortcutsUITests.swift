import XCTest

/// TASK-499: keyboard-shortcut behaviors — ⌘-number Jobs filters, the Keyboard Shortcuts overlay
/// (via the Help menu and bare `?`), and `?`-in-a-text-field suppression. Runs on a graphical
/// session (local or the Tart VM / CI), like the rest of AppUITests.
final class KeyboardShortcutsUITests: XCTestCase {
    private nonisolated(unsafe) static var sharedApp: XCUIApplication?
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        if let existing = Self.sharedApp,
           existing.state == .runningForeground || existing.state == .runningBackground {
            app = existing
            existing.activate()
            Thread.sleep(forTimeInterval: 0.5)
            // Dismiss a shortcuts overlay or stray window left by a prior test.
            existing.typeKey(.escape, modifierFlags: [])
        } else {
            app = launchApp()
            Self.sharedApp = app
        }
    }

    override func tearDown() {
        app?.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
        app = nil
        super.tearDown()
    }

    private var jobsContent: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "content.jobs").firstMatch
    }

    private var overlay: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "overlay.keyboardShortcuts").firstMatch
    }

    // MARK: - ⌘-number Jobs filters (AC#1/#2)

    func testCommand1NavigatesToAllJobs() {
        navigate(app, label: "Dashboard")
        XCTAssertTrue(
            waitUntil(timeout: 8) { !self.jobsContent.exists },
            "prerequisite: leave the Jobs section before ⌘1"
        )
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(jobsContent.waitForExistence(timeout: 5), "⌘1 should navigate to All Jobs")
    }

    func testCommand2NavigatesToJobsNewFilter() {
        navigate(app, label: "Dashboard")
        XCTAssertTrue(waitUntil(timeout: 8) { !self.jobsContent.exists })
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(jobsContent.waitForExistence(timeout: 5), "⌘2 should navigate to the Jobs list (New filter)")
    }

    // MARK: - Overlay via Help menu (AC#10/#11)

    func testHelpMenuOpensAndEscapeDismissesOverlay() {
        let help = app.menuBars.menuBarItems["Help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.click()
        let item = app.menuItems["Keyboard Shortcuts"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Help menu should contain Keyboard Shortcuts")
        item.click()

        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "Keyboard Shortcuts overlay should open")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 5) { !self.overlay.exists },
            "Escape should dismiss the Keyboard Shortcuts overlay"
        )
    }

    // MARK: - Bare `?` (AC#9)

    func testBareQuestionMarkOpensOverlayOutsideTextField() {
        navigate(app, label: "Dashboard") // a section with no focused text field
        app.typeKey(.escape, modifierFlags: []) // ensure no editor has focus
        app.typeText("?")
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "bare ? should open the overlay when not editing text")
        app.typeKey(.escape, modifierFlags: [])
        _ = waitUntil(timeout: 5) { !self.overlay.exists }
    }

    func testQuestionMarkInSearchFieldDoesNotOpenOverlay() {
        // ⌘K focuses the Jobs search field; typing ? there must insert, not open the overlay.
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(jobsContent.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.4)
        app.typeText("?")
        // Give the (incorrect) overlay a chance to appear; it must not.
        XCTAssertFalse(
            overlay.waitForExistence(timeout: 2),
            "typing ? in the search field must insert text, not open the overlay"
        )
    }
}
