import XCTest

/// Full-app screenshot tour — captures every view, detail pane, and settings tab.
/// Run the AppUITests scheme. Screenshots land in screenshots/<timestamp>/ and
/// are also attached to the Xcode test result for inline viewing.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        app = launchApp()
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - 01 Dashboard

    func test01_Dashboard() {
        navigate(app, label: "Dashboard")
        snap(app, "01-dashboard")
    }

    // MARK: - 02-09 Jobs

    func test02_JobsAll() {
        navigate(app, label: "All Jobs")
        // Verify the Jobs list is shown. navigate() now drives section changes via the Go-menu
        // ⌃⌘3 shortcut, which updates the router/content but not the sidebar NSOutlineView's AX
        // selection value — so assert on the content column, not the sidebar row's value.
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "content.jobs").firstMatch
                .waitForExistence(timeout: 5),
            "Jobs list (content.jobs) should be shown after navigating to All Jobs"
        )
        snap(app, "02-jobs-all")
    }

    func test03_JobsAllWithDetail() {
        navigate(app, label: "All Jobs")
        // Scope to the content.jobs outline. `app.cells.element(boundBy: 0)` matches the first cell
        // in the whole window — the Dashboard sidebar row — and clicking it navigates away, so the
        // shot captured the Dashboard instead of a selected job.
        let jobsOutline = app.descendants(matching: .any).matching(identifier: "content.jobs").firstMatch
        let firstRow = jobsOutline.descendants(matching: .cell).firstMatch
        if firstRow.waitForExistence(timeout: 6) {
            firstRow.click()
            // Wait for the detail pane to render at least one text element.
            waitUntil(timeout: 3) { self.app.staticTexts.count > 5 }
        }
        snap(app, "03-jobs-all-with-detail")
    }

    func test07_JobsPursuingSidebar() {
        navigate(app, label: "Pursuing")
        snap(app, "07-jobs-pursuing-sidebar")
    }

    func test08_JobsAppliedSidebar() {
        navigate(app, label: "Applied")
        snap(app, "08-jobs-applied-sidebar")
    }

    func test09_JobsPassedSidebar() {
        navigate(app, label: "Passed")
        snap(app, "09-jobs-passed-sidebar")
    }

    // MARK: - 10 Needs Action

    func test10_NeedsAction() {
        navigate(app, label: "Needs Action")
        snap(app, "10-needs-action")
    }

    // MARK: - 11-12 Sites

    func test11_SitesList() {
        navigate(app, label: "Sites")
        snap(app, "11-sites-list")
    }

    func test12_SitesWithDetail() {
        navigate(app, label: "Sites")
        let firstRow = app.cells.element(boundBy: 0)
        if firstRow.waitForExistence(timeout: 4) {
            firstRow.click()
            waitUntil(timeout: 3) { self.app.staticTexts.count > 5 }
        }
        snap(app, "12-sites-with-detail")
    }

    // MARK: - 13 Duplicates

    func test13_Duplicates() {
        navigate(app, label: "Duplicates")
        // Select the first detected pair so the side-by-side comparison pane is shown (the demo
        // seeds one Amazon duplicate pair). Scope to content.duplicates to avoid the sidebar.
        let list = app.descendants(matching: .any).matching(identifier: "content.duplicates").firstMatch
        let firstPair = list.descendants(matching: .cell).firstMatch
        if firstPair.waitForExistence(timeout: 6) {
            firstPair.click()
            waitUntil(timeout: 3) { self.app.staticTexts.count > 8 }
        }
        snap(app, "13-duplicates")
    }

    // MARK: - 14 LLM Queue

    func test14_LLMQueue() {
        navigate(app, label: "LLM Queue")
        snap(app, "14-llm-queue")
    }

    // MARK: - 15 Data Quality

    func test15_DataQuality() {
        navigate(app, label: "Data Quality")
        snap(app, "15-data-quality")
    }

    // MARK: - 16-18 Settings (now the standard macOS ⌘, preferences window)

    func test16_SettingsGeneral() {
        captureSettingsTab("General", showing: "Appearance", as: "16-settings-general")
    }

    func test16b_SettingsJobs() {
        captureSettingsTab("Jobs", showing: "Location Filter", as: "16b-settings-jobs")
    }

    func test17_SettingsAI() {
        captureSettingsTab("AI", showing: "Provider", as: "17-settings-ai")
    }

    func test17b_SettingsData() {
        captureSettingsTab("Data", showing: "Back Up Data…", as: "17b-settings-data")
    }

    func test17c_SettingsSearch() {
        captureSettingsTab("Search", showing: "What I'm looking for", as: "17c-settings-search")
    }

    func test18_SettingsDebug() {
        captureSettingsTab("Debug", showing: "Environment", as: "18-settings-debug")
    }

    // MARK: - 19 Resumes (promoted to a top-level sidebar section)

    func test19_Resumes() {
        navigate(app, label: "Resumes")
        snap(app, "19-resumes")
    }

    // MARK: - Helpers

    /// Switch to a Settings tab, prove the pane really changed, and only then capture it.
    ///
    /// TASK-716: this tour used to click a query that matched nothing and captured whatever pane was
    /// showing — five identical General screenshots that the suite reported as a pass. Two checks now
    /// gate the capture: the Settings window title (asserted inside `selectSettingsTab`) and a control
    /// that exists only in the target pane. A shot is never written when either fails.
    private func captureSettingsTab(_ tab: String, showing marker: String, as name: String) {
        let window = selectSettingsTab(app, tab)
        // selectSettingsTab already reported the failure; don't capture a mislabelled screenshot.
        guard window.exists, window.title == tab else { return }

        let paneMarker = window.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", marker)).firstMatch
        guard paneMarker.waitForExistence(timeout: 5) else {
            return XCTFail("the \(tab) pane should contain '\(marker)' — not capturing \(name)")
        }
        snapWindow(window, name)
    }
}
