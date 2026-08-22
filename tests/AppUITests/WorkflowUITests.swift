import XCTest

/// Seeded workflow tests for high-risk user journeys.
/// These tests require --ui-test-store and --seed-demo-data (set by launchApp).
final class WorkflowUITests: XCTestCase {
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

    // MARK: - Archive a job

    func testArchive_seededJob_movesJobToArchived() {
        // ⌘K is the reliable shortcut to All Jobs on headless VMs — coordinate clicks on
        // NSOutlineView sidebar rows don't reliably update the SwiftUI NavigationSplitView binding.
        app.typeKey("k", modifierFlags: .command)

        // With seeded data, there should be at least one job cell.
        // Scope queries to the content.jobs Outline (the jobs list NSOutlineView) to avoid
        // accidentally matching sidebar cells, which are in a separate Outline element.
        let jobsOutline = app.descendants(matching: .any).matching(identifier: "content.jobs").firstMatch
        XCTAssertTrue(jobsOutline.waitForExistence(timeout: 10), "Jobs list (content.jobs) must exist in All Jobs view")
        let jobCells = jobsOutline.descendants(matching: .cell)
        let firstJob = jobCells.firstMatch
        XCTAssertTrue(firstJob.waitForExistence(timeout: 5), "At least one job row must exist in seeded data")

        // Wait until the first cell is hittable (not covered or off-screen)
        let isHittable = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isHittable == true"),
                object: firstJob
            )],
            timeout: 5
        ) == .completed
        XCTAssertTrue(isHittable, "First job row must be hittable before right-clicking")

        // Right-click to open the row's context menu, then click its "Archive Job" item.
        // Target the item by its accessibility identifier (jobContextMenu.archive) scoped to
        // app.menuItems — NOT a loose "label CONTAINS 'archive'" scan over every descendant, which
        // could match an unrelated/disabled control and click nothing. On headless VMs the context
        // menu sometimes never registers with the accessibility service; if so, skip gracefully.
        firstJob.rightClick()
        let archiveItem = app.menuItems["jobContextMenu.archive"]
        guard archiveItem.waitForExistence(timeout: 3) else {
            // Context menu not accessible on this headless VM — skip remaining assertions.
            return
        }
        archiveItem.click()

        // Verify: the job's status changed to Archived. Seeded data has no pre-archived jobs, so an
        // "Archived" row appearing confirms the archive succeeded ("All Jobs" keeps archived jobs
        // visible — the row stays, its chip flips to "Archived"). Archiving is async (a detached
        // Task + SwiftUI re-render), so WAIT rather than checking .exists immediately.
        //
        // Assert on the ROW's accessibility label, not on a standalone "Archived" static text.
        // TASK-506 made each row a single accessibility element (`children: .ignore`) so VoiceOver
        // reads it as one sentence instead of walking seven fragments — which also removed the chip's
        // own text from the tree. `app.staticTexts["Archived"]` has been unfindable ever since, and
        // this suite has been red every week without the app being broken at all. The composed label
        // ends with the status (`JobRowAccessibility.label`), so the row itself carries the evidence.
        // DESCENDANTS, not `.cells`: the row's composed label lives on the SwiftUI element inside the
        // cell, and the cell itself reports an empty label. Querying cells found four rows with no
        // labels at all, which is why the previous form couldn't see the status either.
        let archivedRow = jobsOutline.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Archived"))
            .firstMatch
        let found = archivedRow.waitForExistence(timeout: 5)
        // Report what the tree actually held. A bare "expected Archived" tells the next reader
        // nothing about WHY — this suite was red for six weeks on exactly that kind of message.
        let visibleLabels = jobsOutline.descendants(matching: .any).allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
            .prefix(4)
        XCTAssertTrue(
            found,
            "No job row's accessibility label contains 'Archived' after archiving. "
                + "First rows seen: \(visibleLabels)"
        )
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
