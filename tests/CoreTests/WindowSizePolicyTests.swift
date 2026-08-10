import Foundation
import XCTest
@testable import JobhuntCore

/// Which windows get the minimum size (TASK-557).
///
/// The rule lives in Core precisely so it can be tested: the app target has only XCUITest, which
/// needs a graphical session, so an `NSWindow`-shaped rule would have no coverage at all.
final class WindowSizePolicyTests: XCTestCase {
    private func constrain(
        isTitled: Bool = true,
        isResizable: Bool = true,
        isPanel: Bool = false,
        identifier: String? = nil
    ) -> Bool {
        WindowSizePolicy.shouldConstrain(
            isTitled: isTitled, isResizable: isResizable, isPanel: isPanel, identifier: identifier
        )
    }

    func testAnOrdinaryDocumentWindowIsConstrained() {
        XCTAssertTrue(constrain())
    }

    /// A fixed-size window has nothing to floor, and setting a minimum larger than its frame would
    /// force it to grow.
    func testNonResizableWindowsAreLeftAlone() {
        XCTAssertFalse(constrain(isResizable: false))
        XCTAssertFalse(constrain(isTitled: false))
    }

    /// Panels and sheets size themselves from their content.
    func testPanelsAreLeftAlone() {
        XCTAssertFalse(constrain(isPanel: true))
    }

    /// Forcing 900×600 on the Settings window would make it enormous.
    func testSettingsWindowIsExcluded() {
        XCTAssertFalse(constrain(identifier: WindowSizePolicy.settingsWindowIdentifier))
        XCTAssertTrue(constrain(identifier: "some-other-window"))
    }

    /// The floor is the point at which the sidebar and detail panes stop overlapping; a regression
    /// to a smaller number would silently reintroduce the unusable layout.
    func testTheFloorIsTheDocumentedSize() {
        XCTAssertEqual(WindowSizePolicy.minimumWidth, 900)
        XCTAssertEqual(WindowSizePolicy.minimumHeight, 600)
    }
}
