import XCTest

/// Behavior-focused UI tests that assert desktop interaction correctness,
/// not just visual screenshots. Complements ScreenshotTests.swift.
final class BehaviorUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - Sidebar navigation

    func testSidebarNavigationChangesSections() {
        // Start on Dashboard
        navigate(app, label: "Dashboard")
        let dashboardBtn = app.buttons["sidebar.dashboard"].firstMatch
        XCTAssertTrue(dashboardBtn.waitForExistence(timeout: 4), "Dashboard sidebar item should exist")
        XCTAssertTrue(dashboardBtn.isSelected, "Dashboard sidebar item should be selected after navigation")

        // Switch to Data Quality — a non-default section
        navigate(app, label: "Data Quality")
        let dqBtn = app.buttons["sidebar.dataQuality"].firstMatch
        XCTAssertTrue(dqBtn.waitForExistence(timeout: 4), "Data Quality sidebar item should exist")
        XCTAssertTrue(dqBtn.isSelected, "Data Quality sidebar item should be selected after navigation")
        XCTAssertFalse(dashboardBtn.isSelected, "Dashboard should no longer be selected")
    }

    func testSidebarLLMQueueNavigation() {
        navigate(app, label: "LLM Queue")
        let btn = app.buttons["sidebar.llmQueue"].firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 4))
        XCTAssertTrue(btn.isSelected, "LLM Queue should be selected — tests a non-default section menu command path")
    }

    // MARK: - Keyboard shortcut: ⌘K (Search Jobs)

    func testCommandKNavigatesToJobsSection() {
        // Start somewhere other than Jobs
        navigate(app, label: "Dashboard")
        let dashBtn = app.buttons["sidebar.dashboard"].firstMatch
        XCTAssertTrue(dashBtn.waitForExistence(timeout: 4))
        XCTAssertTrue(dashBtn.isSelected)

        // Fire ⌘K
        app.typeKey("k", modifierFlags: .command)

        // Jobs section should now be active
        let jobsBtn = app.buttons["sidebar.jobs.all"].firstMatch
        XCTAssertTrue(jobsBtn.waitForExistence(timeout: 4), "All Jobs sidebar item should exist")
        XCTAssertTrue(jobsBtn.isSelected, "⌘K should navigate to All Jobs")
    }

    // MARK: - Keyboard shortcut: ⌘, (Settings)

    func testCommandCommaOpensSettingsWindow() {
        let initialWindowCount = app.windows.count

        app.typeKey(",", modifierFlags: .command)

        // Wait for the Settings window to appear rather than sleeping a fixed duration.
        XCTAssertTrue(
            waitUntil(timeout: 5) { app.windows.count > initialWindowCount },
            "⌘, should open the Settings window"
        )
    }

    // MARK: - Filter chip accessible selected state

    func testRemoteFilterChipAccessibleState() {
        navigate(app, label: "All Jobs")

        // The "Remote" filter chip must exist in the Jobs filter bar.
        let remoteChip = app.buttons["Remote"].firstMatch
        XCTAssertTrue(remoteChip.waitForExistence(timeout: 5),
                      "Remote filter chip not found in Jobs filter bar — chip is missing or filter bar is not rendered")

        // Initially not selected
        XCTAssertEqual(remoteChip.value as? String, "off", "Remote chip should start as 'off'")
        XCTAssertFalse(remoteChip.isSelected, "Remote chip should not be selected initially")

        // Activate it
        remoteChip.click()
        XCTAssertTrue(waitUntil(timeout: 2) { remoteChip.value as? String == "on" },
                      "Remote chip should report 'on' after activation")
        XCTAssertTrue(remoteChip.isSelected, "Remote chip should report isSelected after activation")

        // Deactivate it
        remoteChip.click()
        XCTAssertTrue(waitUntil(timeout: 2) { remoteChip.value as? String == "off" },
                      "Remote chip should report 'off' after deactivation")
        XCTAssertFalse(remoteChip.isSelected, "Remote chip should not be selected after deactivation")
    }

    func testDataQualityFilterChipAccessibleState() {
        navigate(app, label: "Data Quality")

        // "Missing Title" is the first filter chip in DataQualityView and must be present.
        let chip = app.buttons["Missing Title"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5),
                      "Data Quality 'Missing Title' filter chip not found — chip is missing or view did not load")

        XCTAssertEqual(chip.value as? String, "off", "Missing Title chip should start as 'off'")

        chip.click()
        XCTAssertTrue(waitUntil(timeout: 2) { chip.value as? String == "on" },
                      "Missing Title chip should report 'on' after activation")
        XCTAssertTrue(chip.isSelected, "Missing Title chip isSelected should be true")

        chip.click()
        XCTAssertTrue(waitUntil(timeout: 2) { chip.value as? String == "off" },
                      "Missing Title chip should report 'off' after deactivation")
        XCTAssertFalse(chip.isSelected, "Missing Title chip isSelected should be false after deactivation")
    }
}
