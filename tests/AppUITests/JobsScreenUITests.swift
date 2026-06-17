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

    // NOTE: the menu-bar "Jobs" CommandMenu (TASK-114 AC#5) was intentionally removed in 388097b
    // ("remove menu-bar Jobs menu") — its actions moved to the toolbar + right-click menu, and the
    // removal cleared a Cmd-R collision with the Data Quality menu. The former testJobsMenuCommandsExist
    // was deleted with it; archiving via the row context menu is covered by WorkflowUITests.
}
