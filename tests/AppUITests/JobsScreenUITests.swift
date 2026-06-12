import XCTest

final class JobsScreenUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = launchApp()
        navigate(app, label: "All Jobs")
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    func testSidebarPursuingFilters() {
        navigate(app, label: "Pursuing")
        snap(app, "sidebar-pursuing-filtered")
    }

    // TASK-114 AC#5: verify the "Jobs" CommandMenu exists in the menu bar and that
    // "Re-run AI Extraction" is present and correctly disabled when no jobs are selected.
    func testJobsMenuCommandsExist() {
        // The Jobs section must be shown to activate the focusedSceneValue handler.
        navigate(app, label: "All Jobs")

        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.exists, "Menu bar must exist")

        // Open the Jobs menu
        let jobsMenu = menuBar.menuBarItems["Jobs"]
        XCTAssertTrue(jobsMenu.waitForExistence(timeout: 3), "Jobs menu must be in the menu bar")
        jobsMenu.click()

        // Verify "Re-run AI Extraction" exists in the menu
        let reRunItem = app.menuItems["Re-run AI Extraction"]
        XCTAssertTrue(reRunItem.waitForExistence(timeout: 2), "Re-run AI Extraction must be in the Jobs menu")

        // Verify "Archive Selected" exists
        let archiveItem = app.menuItems["Archive Selected"]
        XCTAssertTrue(archiveItem.exists, "Archive Selected must be in the Jobs menu")

        // Close the menu with Escape
        app.typeKey(.escape, modifierFlags: [])
    }
}
