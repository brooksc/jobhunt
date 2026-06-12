import XCTest

// Run UI tests locally:
//   xcodebuild test -scheme Jobhunt -destination 'platform=macOS' -only-testing AppUITests
// Run on a macOS CI runner (e.g. GitHub Actions macos-latest):
//   same command; requires a graphical display session (use macos-latest runner, not Linux)

// One timestamped folder shared across all tests in a process run.
// Written to /tmp first (always writable from test runner), then logged so
// the caller can move/copy it to the project directory if desired.
let screenshotDir: URL = {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = tmp.appendingPathComponent("jobhunt-screenshots/\(fmt.string(from: Date()))")
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("SCREENSHOT_DIR: \(dir.path)")
    } catch {
        print("SCREENSHOT_DIR_ERROR: \(error)")
    }
    return dir
}()

extension XCTestCase {

    // MARK: - State-based wait

    /// Poll until `check()` returns true or `timeout` elapses. Returns whether the condition was met.
    @discardableResult
    func waitUntil(timeout: TimeInterval = 4, _ check: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if check() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        return check()
    }

    // MARK: - Launch

    func launchApp(seedData: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UIAnimationDragCoefficient", "0", "--ui-test-store"]
        if seedData { app.launchArguments.append("--seed-demo-data") }
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 10)
        // Wait for the sidebar to be ready rather than sleeping a fixed duration.
        _ = app.buttons["sidebar.dashboard"].firstMatch.waitForExistence(timeout: 8)
        return app
    }

    /// Assert an element exists or fail immediately with a descriptive message.
    func requireElement(_ element: XCUIElement, _ description: String, timeout: TimeInterval = 5) {
        XCTAssert(element.waitForExistence(timeout: timeout), "Required UI element missing: \(description)")
    }

    // MARK: - Sidebar navigation

    /// Map from display label → accessibilityIdentifier set in Sidebar.swift.
    private static let sidebarIDs: [String: String] = [
        "Dashboard":    "sidebar.dashboard",
        "Needs Action": "sidebar.needsAction",
        "All Jobs":     "sidebar.jobs.all",
        "New":          "sidebar.jobs.new",
        "Pursuing":     "sidebar.jobs.pursuing",
        "Applied":      "sidebar.jobs.applied",
        "Interview":    "sidebar.jobs.interview",
        "Offer":        "sidebar.jobs.offer",
        "Rejected":     "sidebar.jobs.rejected",
        "Passed":       "sidebar.jobs.passed",
        "Closed":       "sidebar.jobs.closed",
        "Expired":      "sidebar.jobs.expired",
        "Sites":        "sidebar.sites",
        "Duplicates":   "sidebar.duplicates",
        "LLM Queue":    "sidebar.llmQueue",
        "Data Quality": "sidebar.dataQuality",
        "Settings":     "sidebar.settings",
    ]

    /// Navigate the macOS sidebar to the item with the given display label.
    /// Uses accessibilityIdentifier as the primary lookup so items that are
    /// scrolled off-screen (outside SwiftUI's lazy render window) can still
    /// be found and scrolled into view before clicking.
    func navigate(_ app: XCUIApplication, label: String) {
        // 1. Try by accessibility identifier — works even when off-screen.
        if let id = Self.sidebarIDs[label] {
            let btn = app.buttons[id].firstMatch
            if btn.waitForExistence(timeout: 4) {
                btn.click()
                // Wait for the button to reflect selected state rather than sleeping.
                waitUntil(timeout: 3) { btn.isSelected }
                return
            }
        }

        // 2. Fallback: find by static text (covers items not in the map above).
        let text = app.staticTexts[label].firstMatch
        if text.waitForExistence(timeout: 4) {
            text.click()
            // No isSelected to poll on a staticText; give the view a moment to load.
            waitUntil(timeout: 2) { app.cells.count > 0 || app.staticTexts.count > 2 }
            return
        }

        XCTFail("Could not find sidebar item with label: \(label)")
    }

    // MARK: - Screenshots

    /// Capture the app window, save to disk, and attach to test results.
    func snap(_ app: XCUIApplication, _ name: String) {
        let window = app.windows.firstMatch
        let shot = window.exists ? window.screenshot() : app.screenshot()
        writeToDisk(shot, name: name)
    }

    /// Capture a specific element (e.g. the Settings window).
    func snapElement(_ element: XCUIElement, _ name: String) {
        let shot = element.screenshot()
        writeToDisk(shot, name: name)
    }

    private func writeToDisk(_ shot: XCUIScreenshot, name: String) {
        let file = screenshotDir.appendingPathComponent("\(name).png")
        do {
            try shot.pngRepresentation.write(to: file)
        } catch {
            XCTContext.runActivity(named: "Screenshot write failed: \(error)") { _ in }
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
