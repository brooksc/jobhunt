import XCTest

/// TASK-572: selecting a saved search must keep it active (the bookmark chip / sidebar selection)
/// rather than being immediately reinterpreted as an ad hoc token search, and must clear prior
/// session-only filters. The token-retention policy is unit-tested in `SavedSearchTokenIDTests`;
/// these tests cover the view integration and visible selection state.
final class SavedSearchUITests: XCTestCase {
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

    /// Selecting a saved search that maps to status tokens keeps it active: the bookmark chip appears
    /// instead of the token-change observer immediately clearing the selection (the TASK-572 bug).
    func testSelectingSavedSearchWithTokensStaysActive() {
        selectSavedSearch("Active Pipeline")
        XCTAssertTrue(
            savedSearchChip.waitForExistence(timeout: 5),
            "Selecting a saved search with status tokens should leave it active (bookmark chip shown)."
        )
    }

    /// Applying a session-only filter (a remote toggle in the advanced-filters popover) and then
    /// selecting a saved search leaves the saved search active — the prior session filter is reset by
    /// the atomic apply rather than continuing to narrow the list.
    func testSelectingSavedSearchAfterSessionFilterStaysActive() {
        let filterButton = app.buttons["Advanced filters"].firstMatch
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5), "Advanced filters toolbar button should exist.")

        // Open the popover, and open it again if the first click didn't take (TASK-720). This failed
        // 3/3 attempts on the macos-latest runner while passing in the macOS 26 VM, so the cause is
        // environmental — a toolbar click that lands before the button is ready, or a popover that
        // presents more slowly under CI load — rather than anything about the app. Retrying the open
        // covers both without pretending to know which; a popover that genuinely never presents still
        // fails, because the assertion below is unchanged.
        // TASK-720 experiment: which click opens the popover on the runner?
        // BehaviorUITests opens this same popover with a PLAIN click and passes on CI; this test used
        // a coordinate click and fails with popovers=0. Geometry is identical on both (window
        // 1079x674, button (852,31,75,52), hittable=true), so delivery is the only difference left.
        let remote = element("filter.remote.remote")
        print("DIAG A: plain click")
        filterButton.click()
        _ = remote.waitForExistence(timeout: 8)
        print("DIAG A result popovers=\(app.popovers.count) remote=\(remote.exists)")

        if !remote.exists {
            print("DIAG B: coordinate click")
            filterButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            _ = remote.waitForExistence(timeout: 8)
            print("DIAG B result popovers=\(app.popovers.count) remote=\(remote.exists)")
        }
        if !remote.exists {
            print("DIAG C: press")
            filterButton.press(forDuration: 0.05)
            _ = remote.waitForExistence(timeout: 8)
            print("DIAG C result popovers=\(app.popovers.count) remote=\(remote.exists)")
        }
        print("DIAG windows=\(app.windows.count) frontmost=\(app.state.rawValue)")
        XCTAssertTrue(remote.exists, "Remote filter toggle should appear in the popover.")
        remote.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey(.escape, modifierFlags: []) // dismiss the popover
        Thread.sleep(forTimeInterval: 0.3)

        selectSavedSearch("Remote Only — High Fit")
        XCTAssertTrue(
            savedSearchChip.waitForExistence(timeout: 5),
            "A saved search selected after a session-only filter should be active (bookmark chip shown)."
        )
    }

    // MARK: - Helpers

    private var savedSearchChip: XCUIElement {
        element("chip.savedSearch")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func selectSavedSearch(_ name: String) {
        let row = element("sidebar.savedSearch.\(name)")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saved-search sidebar row '\(name)' should exist.")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        Thread.sleep(forTimeInterval: 0.5)
    }
}
