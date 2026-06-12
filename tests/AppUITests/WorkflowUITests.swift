import XCTest

/// Seeded workflow tests for high-risk user journeys.
/// These tests require --ui-test-store and --seed-demo-data (set by launchApp).
final class WorkflowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ui-test-store", "--seed-demo-data"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - Archive a job

    func testArchive_seededJob_movesJobToArchived() {
        // Navigate to All Jobs
        let allJobsSidebar = app.outlineRows.containing(.staticText, identifier: "All Jobs").firstMatch
        if allJobsSidebar.exists { allJobsSidebar.click() }

        // With seeded data, there should be at least one job cell
        let firstJob = app.cells.firstMatch
        XCTAssertTrue(firstJob.waitForExistence(timeout: 5), "At least one job row must exist in seeded data")

        // Record the initial cell count
        let countBefore = app.cells.count

        // Right-click to open context menu
        firstJob.rightClick()

        // Archive action must exist — fail explicitly if it doesn't
        let archiveItem = app.menuItems.matching(
            NSPredicate(format: "label CONTAINS[c] 'archive'")
        ).firstMatch
        XCTAssertTrue(
            archiveItem.waitForExistence(timeout: 3),
            "Archive menu item not found in context menu — seeded jobs must have an Archive action"
        )
        archiveItem.click()

        // After archiving, the row should disappear from All Jobs view (archived jobs are filtered out)
        // or the cell count should decrease.
        let rowGone = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count < %d", countBefore),
                object: app.cells
            )],
            timeout: 5
        ) == .completed
        XCTAssertTrue(rowGone, "Job row count should decrease after archiving (archived jobs filtered from All Jobs view)")
    }

    // MARK: - Seeded data health check

    func testSeededData_jobsPresent() {
        let hasJobs = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count > 0"),
                object: app.cells
            )],
            timeout: 5
        ) == .completed
        XCTAssertTrue(hasJobs, "Seeded store must have at least one job")
    }
}
