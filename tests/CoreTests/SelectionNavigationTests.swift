import XCTest
@testable import JobhuntCore

final class SelectionNavigationTests: XCTestCase {
    private let order = ["a", "b", "c", "d", "e"]

    func testRemovingMiddleFocusesNextSurvivor() {
        XCTAssertEqual(SelectionNavigation.nextSelection(order: order, removing: ["c"]), "d")
    }

    func testRemovingLastFallsBackToPrecedingSurvivor() {
        XCTAssertEqual(SelectionNavigation.nextSelection(order: order, removing: ["e"]), "d")
    }

    func testRemovingOnlyRowReturnsNil() {
        XCTAssertNil(SelectionNavigation.nextSelection(order: ["a"], removing: ["a"]))
    }

    func testRemovingAllRowsReturnsNil() {
        XCTAssertNil(SelectionNavigation.nextSelection(order: order, removing: Set(order)))
    }

    func testMultiSelectionFocusesFirstSurvivorAfterLastRemoved() {
        // Remove b and d — focus lands after the last removed (d) → e.
        XCTAssertEqual(SelectionNavigation.nextSelection(order: order, removing: ["b", "d"]), "e")
    }

    func testContiguousTailRemovalFallsBackBeforeBlock() {
        // Remove d and e (the tail) — nearest preceding survivor is c.
        XCTAssertEqual(SelectionNavigation.nextSelection(order: order, removing: ["d", "e"]), "c")
    }

    func testRemovingNothingReturnsNil() {
        XCTAssertNil(SelectionNavigation.nextSelection(order: order, removing: []))
    }

    func testUnknownIDsAreIgnored() {
        XCTAssertNil(SelectionNavigation.nextSelection(order: order, removing: ["zzz"]))
    }
}
