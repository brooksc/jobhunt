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
        Thread.sleep(forTimeInterval: 0.5)
        snap(app, "sidebar-pursuing-filtered")
    }
}
