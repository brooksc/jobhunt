import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-649: the two Jobs-list filter rules with non-obvious semantics.
final class JobFilterRulesTests: XCTestCase {
    // MARK: - Remote type

    func testNilSelectionMatchesEverything() {
        for type: RemoteType? in [.remote, .hybrid, .onsite, .unknown, nil] {
            XCTAssertTrue(JobFilterRules.matchesRemote(type, selected: nil), String(describing: type))
        }
    }

    func testRemoteSelectionMatchesOnlyThatType() {
        XCTAssertTrue(JobFilterRules.matchesRemote(.remote, selected: [.remote]))
        XCTAssertFalse(JobFilterRules.matchesRemote(.onsite, selected: [.remote]))
        XCTAssertTrue(JobFilterRules.matchesRemote(.onsite, selected: [.remote, .onsite]))
    }

    /// The bug this fixes: a job with no stored remote type matched no filter at all, so the ~40 such
    /// jobs were unreachable. A missing value is semantically "unknown".
    func testMissingRemoteTypeIsTreatedAsUnknown() {
        XCTAssertTrue(JobFilterRules.matchesRemote(nil, selected: [.unknown]))
        XCTAssertFalse(JobFilterRules.matchesRemote(nil, selected: [.remote]))
        XCTAssertTrue(JobFilterRules.matchesRemote(.unknown, selected: [.unknown]))
    }

    // MARK: - Location criteria (tri-state)

    func testCriteriaAnyMatchesEverything() {
        for stored: Bool? in [true, false, nil] {
            XCTAssertTrue(JobFilterRules.matchesCriteria(stored: stored, wanted: nil))
        }
    }

    func testCriteriaMeetsAndDoesNotMeetArePartitioned() {
        XCTAssertTrue(JobFilterRules.matchesCriteria(stored: true, wanted: true))
        XCTAssertFalse(JobFilterRules.matchesCriteria(stored: false, wanted: true))
        XCTAssertTrue(JobFilterRules.matchesCriteria(stored: false, wanted: false))
        XCTAssertFalse(JobFilterRules.matchesCriteria(stored: true, wanted: false))
    }

    /// A job whose verdict was never computed (extraction failed) must not be swept into the
    /// "doesn't meet" review pile — that would assert something the data doesn't support.
    func testUncomputedVerdictMatchesNeitherSide() {
        XCTAssertFalse(JobFilterRules.matchesCriteria(stored: nil, wanted: true))
        XCTAssertFalse(JobFilterRules.matchesCriteria(stored: nil, wanted: false))
    }

    // MARK: - The live triage case

    /// End-to-end shape of the user's workflow: with onsite disallowed, `LocationCriteria` marks an
    /// unknown/absent remote type as not meeting criteria, and the "Doesn't meet" filter selects it.
    func testUnknownRemoteTypeLandsInTheDoesNotMeetPile() {
        for type: RemoteType? in [.unknown, nil, .onsite] {
            let meets = LocationCriteria.meets(
                remoteType: type, location: "San Francisco, CA", preferredLocations: "",
                allowRemote: true, allowHybrid: false, allowOnsite: false, filterEnabled: true
            )
            XCTAssertFalse(meets, "\(String(describing: type)) should not meet remote-only criteria")
            XCTAssertTrue(
                JobFilterRules.matchesCriteria(stored: meets, wanted: false),
                "and must be selectable via the Doesn't-meet filter"
            )
        }
        // A genuinely remote job stays out of that pile.
        let remoteMeets = LocationCriteria.meets(
            remoteType: .remote, location: "Remote - USA", preferredLocations: "",
            allowRemote: true, allowHybrid: false, allowOnsite: false, filterEnabled: true
        )
        XCTAssertTrue(remoteMeets)
        XCTAssertFalse(JobFilterRules.matchesCriteria(stored: remoteMeets, wanted: false))
    }
}
