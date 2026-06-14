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
        // Terminate any lingering macOS crash reporter dialogs.
        let crashReporter = XCUIApplication(bundleIdentifier: "com.apple.DiagnosticsReporter")
        if crashReporter.state != .notRunning {
            crashReporter.terminate()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        }

        // On fresh headless VMs the accessibility service is cold and can take 200+ seconds
        // to register a new app's windows. Opening a Finder window first exercises the
        // accessibility service and reduces Jobhunt's window registration to ~30-60 seconds.
        // Note: Finder may already be frontmost on VM startup — always open a window to
        // ensure the accessibility service processes real window content.
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("n", modifierFlags: .command) // ⌘N opens a new Finder window
        if finder.windows.firstMatch.waitForExistence(timeout: 20) {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 2.0))
            finder.typeKey("w", modifierFlags: .command) // ⌘W closes the Finder window
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }

        let app = XCUIApplication()
        // -ApplePersistenceIgnoreState YES disables AppKit window-state restoration. Without it,
        // a reused VM (or a prior run that quit windowless) restores "no windows", so the
        // WindowGroup opens zero windows and the main window / sidebar.dashboard never appear.
        app.launchArguments += [
            "-UIAnimationDragCoefficient", "0",
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-store",
        ]
        if seedData { app.launchArguments.append("--seed-demo-data") }
        app.launch()
        app.activate()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))

        // Poll for both the window and sidebar.dashboard together, clicking the window as
        // soon as it appears (the click triggers SwiftUI tree hydration). Calling activate()
        // each iteration keeps the app prioritized with the accessibility service.
        var dashboardEl = app.descendants(matching: .any).matching(identifier: "sidebar.dashboard").firstMatch
        let deadline = Date(timeIntervalSinceNow: 600)
        var windowClicked = false

        // Require 5 consecutive 1-second checks where dashboard.exists = true before
        // returning. RunLoop.current.run(until:) can return early due to accessibility events,
        // producing false-positive stability readings. Thread.sleep guarantees genuine 1-second
        // gaps so all 5 checks represent distinct seconds of accessibility tree stability.
        var stableCount = 0
        while stableCount < 5 && Date() < deadline {
            if dashboardEl.exists {
                stableCount += 1
                Thread.sleep(forTimeInterval: 1.0)
            } else {
                stableCount = 0
                if !windowClicked {
                    let window = app.windows.firstMatch
                    if window.exists {
                        window.click()
                        Thread.sleep(forTimeInterval: 0.5)
                        // NavigationSplitView persists sidebar visibility; restore if collapsed.
                        let showSidebar = app.buttons["Show Sidebar"].firstMatch
                        if showSidebar.waitForExistence(timeout: 5) {
                            showSidebar.click()
                            Thread.sleep(forTimeInterval: 0.5)
                        }
                        windowClicked = true
                    }
                }
                app.activate()
                Thread.sleep(forTimeInterval: 2.0)
            }
        }

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

    /// Ordered sidebar items (mirrors Sidebar.swift, section headers excluded —
    /// NSOutlineView keyboard navigation skips group rows going Down AND Up).
    /// Index 0 = Dashboard. Going Down from Dashboard, each subsequent item is
    /// reached by exactly one more Down press (section headers are skipped).
    private static let sidebarOrder: [String] = [
        "Dashboard", "Needs Action",
        "All Jobs", "New", "Pursuing", "Applied", "Interview", "Offer",
        "Rejected", "Passed", "Archived", "Closed", "Expired",
        "Sites", "Duplicates",
        "LLM Queue", "Data Quality", "Settings",
    ]

    /// Navigate the macOS sidebar to the item with the given display label.
    ///
    /// On macOS, SwiftUI List(.sidebar) renders via NSOutlineView. Synthesized XCUI
    /// mouse clicks on outlineRows don't reliably trigger the SwiftUI selection binding.
    /// Arrow-key navigation from a focused NSOutlineView DOES update the binding.
    ///
    /// Anchor: Dashboard (index 0) — always at the top of the sidebar.
    /// Uses coordinate-based clicks to bypass the isHittable check — on headless VMs,
    /// elements can be non-hittable (window not the macOS key window) even when they exist.
    /// coordinate().click() synthesizes a screen-position click regardless of key window state.
    func navigate(_ app: XCUIApplication, label: String) {
        app.activate()
        // Release keyboard focus from any content-area element (e.g., Data Quality list after
        // a chip click). app.activate() can restore the previously-focused element; ESC clears
        // it so the subsequent window click reliably focuses the sidebar NSOutlineView.
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        // Expand sidebar if it was collapsed by a previous action.
        let showSidebarBtn = app.buttons["Show Sidebar"].firstMatch
        if showSidebarBtn.exists {
            showSidebarBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Click the main window to trigger SwiftUI accessibility tree hydration.
        // On cold VM boots and after secondary windows open/close, the accessibility
        // service may not re-register the sidebar elements without a click. This
        // matches what launchApp() does to prime the tree on first launch.
        let mainWin = app.windows.firstMatch
        if mainWin.exists {
            mainWin.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.10)).click()
            Thread.sleep(forTimeInterval: 1.0)
        }

        guard let id = Self.sidebarIDs[label],
              let targetIdx = Self.sidebarOrder.firstIndex(of: label) else {
            // Unknown item — try clicking by label text.
            let text = app.staticTexts[label].firstMatch
            if text.waitForExistence(timeout: 4) {
                text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            } else {
                XCTFail("Could not find sidebar item with label: \(label)")
            }
            return
        }

        // Wait until sidebar.dashboard exists — confirms the sidebar is rendered and accessible.
        let anchorId = Self.sidebarIDs["Dashboard"]!
        let anchorEl = app.descendants(matching: .any).matching(identifier: anchorId).firstMatch
        guard anchorEl.waitForExistence(timeout: 60) else {
            XCTFail("Could not find Dashboard sidebar anchor element")
            return
        }

        // Click the Dashboard outline row to focus the sidebar NSOutlineView from a known position.
        // Using anchorEl (Dashboard) rather than a raw window coordinate avoids two failure modes:
        //   1. A fixed window coordinate can land on a Jobs-status row (e.g. "Offer"), which triggers
        //      the Jobs content NSOutlineView to appear and steal keyboard focus away from the sidebar.
        //   2. DashboardView has no content NSOutlineView, so once we land on Dashboard the sidebar
        //      retains keyboard focus and Down arrows navigate the sidebar reliably.
        let dashboardRow = app.outlineRows.containing(.any, identifier: anchorId).firstMatch
        if dashboardRow.exists {
            dashboardRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            Thread.sleep(forTimeInterval: 0.5)
        } else {
            // Fallback: window-coordinate click if Dashboard row isn't in the accessibility tree yet.
            let mainWin = app.windows.firstMatch
            if mainWin.exists {
                mainWin.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.10)).click()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        if targetIdx == 0 { return }  // Already at Dashboard

        // Navigate from Dashboard to the target by pressing Down targetIdx times.
        for i in 0..<targetIdx {
            app.typeKey(.downArrow, modifierFlags: [])
            Thread.sleep(forTimeInterval: i == targetIdx - 1 ? 0.3 : 0.05)
        }

        // Verify keyboard nav landed on the target (falls through to fallback if it didn't).
        let targetEl = app.descendants(matching: .any).matching(identifier: id).firstMatch
        if targetEl.exists && targetEl.value as? String == "1" { return }

        // Keyboard nav didn't update sidebar selection (focus may have been on content area).
        // Fall back to coordinate click on the target's outline row, then the element itself.
        let row = app.outlineRows.containing(.any, identifier: id).firstMatch
        if row.exists {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            Thread.sleep(forTimeInterval: 0.3)
            return
        }
        if targetEl.exists {
            targetEl.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            Thread.sleep(forTimeInterval: 0.3)
        }
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
