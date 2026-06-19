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
        let firstRow = app.cells.element(boundBy: 0)
        if firstRow.waitForExistence(timeout: 4) {
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
        openSettingsWindow()
        clickSettingsTab(label: "Settings")
        snap(app, "16-settings-general")
    }

    func test17_SettingsLLM() {
        openSettingsWindow()
        clickSettingsTab(label: "LLM")
        snap(app, "17-settings-llm")
    }

    func test18_SettingsDebug() {
        openSettingsWindow()
        clickSettingsTab(label: "Debug")
        snap(app, "18-settings-debug")
    }

    // MARK: - 19 Resumes (promoted to a top-level sidebar section)

    func test19_Resumes() {
        navigate(app, label: "Resumes")
        snap(app, "19-resumes")
    }

    // MARK: - Helpers

    /// Open the standard macOS Settings window via ⌘, and wait for it to appear.
    private func openSettingsWindow() {
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        _ = app.windows["Settings"].waitForExistence(timeout: 5)
    }

    /// Click a settings tab by label. The TabView tabs are radio buttons in the Settings window.
    private func clickSettingsTab(label: String) {
        let pred = NSPredicate(format: "label CONTAINS[c] %@", label)
        let btn = app.radioButtons.matching(pred).firstMatch
        if btn.waitForExistence(timeout: 4) {
            btn.click()
            waitUntil(timeout: 3) { btn.isSelected }
        }
    }
}
