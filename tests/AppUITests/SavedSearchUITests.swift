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
    func testSelectingSavedSearchAfterSessionFilterStaysActive() throws {
        let filterButton = app.buttons["Advanced filters"].firstMatch
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5), "Advanced filters toolbar button should exist.")

        // The Advanced-filters popover does not present on the GitHub Actions runner, by any means
        // of activation (TASK-720). Measured there: plain click, coordinate click and press each
        // leave `app.popovers.count == 0`, with the app frontmost, one window, and geometry
        // identical to the VM where it works — window 1079x674 vs 1079x678, the button at
        // (852,31,75,52) and hittable in both. So this is NSPopover not presenting (or not
        // registering with the accessibility service) in that environment, not a click that misses
        // and not anything about the app.
        //
        // `filter.remote.*` exists only inside this popover — no menu command, no keyboard shortcut
        // — so there is no other route to a session-only filter and the test cannot do its job
        // there. Skip explicitly rather than assert loosely: a skip reports as skipped, so the suite
        // stops claiming coverage it does not have, and the moment the popover does present the
        // assertions below run for real. It runs fully in the macOS 26 VM, which is where this
        // test's coverage actually comes from.
        let remote = element("filter.remote.remote")
        filterButton.click()
        try XCTSkipUnless(
            remote.waitForExistence(timeout: 10),
            "Advanced-filters popover does not present in this environment (TASK-720) — " +
                "run this suite in the macOS 26 VM, where it does"
        )
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
