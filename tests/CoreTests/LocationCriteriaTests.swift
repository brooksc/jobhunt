import XCTest
@testable import JobhuntCore

/// TASK-464: meets_criteria computation (Electron applyLocationFilter parity).
final class LocationCriteriaTests: XCTestCase {
    private func meets(
        _ remote: RemoteType?, location: String? = nil, preferred: String? = nil,
        allowRemote: Bool = true, allowHybrid: Bool = true, allowOnsite: Bool = true,
        enabled: Bool = true
    ) -> Bool {
        LocationCriteria.meets(
            remoteType: remote, location: location, preferredLocations: preferred,
            allowRemote: allowRemote, allowHybrid: allowHybrid, allowOnsite: allowOnsite,
            filterEnabled: enabled)
    }

    func testFilterDisabled_alwaysMeets() {
        XCTAssertTrue(meets(.onsite, allowOnsite: false, enabled: false))
    }

    // No preferred terms → gate on remote mode only.

    func testNoTerms_remoteGatedOnAllowRemote() {
        XCTAssertTrue(meets(.remote, allowRemote: true))
        XCTAssertFalse(meets(.remote, allowRemote: false))
    }

    func testNoTerms_hybridGatedOnAllowHybrid() {
        XCTAssertTrue(meets(.hybrid, allowHybrid: true))
        XCTAssertFalse(meets(.hybrid, allowHybrid: false))
    }

    func testNoTerms_onsiteAndUnknownGatedOnAllowOnsite() {
        XCTAssertFalse(meets(.onsite, allowOnsite: false))
        XCTAssertFalse(meets(.unknown, allowOnsite: false))
        XCTAssertFalse(meets(nil, allowOnsite: false))
        XCTAssertTrue(meets(.onsite, allowOnsite: true))
    }

    // Preferred terms set → remote ignores them; others require a location match.

    func testTerms_remoteIgnoresLocationMatch() {
        XCTAssertTrue(meets(.remote, location: "Mars", preferred: "Austin", allowRemote: true))
        XCTAssertFalse(meets(.remote, location: "Austin", preferred: "Austin", allowRemote: false))
    }

    func testTerms_onsiteRequiresMatch() {
        XCTAssertTrue(meets(.onsite, location: "Austin, TX", preferred: "Austin"))
        XCTAssertFalse(meets(.onsite, location: "Seattle, WA", preferred: "Austin"))
    }

    func testTerms_hybridRequiresAllowAndMatch() {
        XCTAssertTrue(meets(.hybrid, location: "Austin", preferred: "Austin", allowHybrid: true))
        XCTAssertFalse(meets(.hybrid, location: "Austin", preferred: "Austin", allowHybrid: false))
        XCTAssertFalse(meets(.hybrid, location: "Denver", preferred: "Austin", allowHybrid: true))
    }

    func testTerms_unknownRequiresOnsiteAllowAndMatch() {
        XCTAssertTrue(meets(nil, location: "Austin", preferred: "Austin", allowOnsite: true))
        XCTAssertFalse(meets(nil, location: "Austin", preferred: "Austin", allowOnsite: false))
    }
}
