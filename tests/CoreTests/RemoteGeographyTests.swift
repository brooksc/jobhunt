import XCTest
@testable import JobhuntCore

/// A remote posting used to meet the location criteria no matter where remote was offered, so
/// Europe-only roles (job #341, Nebius, "Amsterdam") looked qualified in Interested with no way to
/// filter them out. These pin the deliberately asymmetric rule: only positively-foreign locations
/// are ruled out; anything unrecognised keeps passing.
final class RemoteGeographyTests: XCTestCase {
    private func classify(_ location: String?, preferred: String = "United States") -> RemoteGeography.Verdict {
        RemoteGeography.classify(location: location, preferredTerms: parsePreferredLocations(preferred))
    }

    // MARK: - Out of bounds

    func testReportedCaseIsRuledOut() {
        XCTAssertEqual(classify("Amsterdam"), .outOfBounds)
    }

    func testForeignCountriesAndRegionsAreRuledOut() {
        for location in [
            "Netherlands",
            "Remote - EMEA",
            "Europe",
            "London, United Kingdom",
            "Bengaluru, India",
            "Remote (Colombia)",
            "Tokyo",
            "Sydney, Australia"
        ] {
            XCTAssertEqual(classify(location), .outOfBounds, location)
        }
    }

    // MARK: - Eligible

    func testUSLocationsAreEligible() {
        for location in [
            "United States",
            "Remote, US",
            "San Francisco, CA",
            "Austin, TX",
            "New York City",
            "Boston or Pittsburgh",
            "Louisville, KY; Tampa, FL"
        ] {
            XCTAssertEqual(classify(location), .eligible, location)
        }
    }

    /// A posting open to several regions including one the user matches is NOT foreign-only. This is
    /// why eligibility is checked before the foreign pass.
    func testMixedRegionPostingsStayEligible() {
        XCTAssertEqual(classify("EMEA and AMER time zones"), .eligible)
        XCTAssertEqual(classify("Toronto, San Francisco, London, New York City, Seoul, Paris"), .eligible)
        XCTAssertEqual(classify("Remote - US or Canada"), .eligible)
    }

    func testPreferredTermWinsEvenWhenForeign() {
        XCTAssertEqual(classify("Berlin, Germany", preferred: "Berlin"), .eligible)
    }

    // MARK: - Indeterminate (must keep passing)

    func testVagueLocationsAreIndeterminate() {
        for location in ["", "Global", "Multiple Locations", "Not specified", "Anywhere", "Remote"] {
            XCTAssertEqual(classify(location), .indeterminate, location)
        }
        XCTAssertEqual(classify(nil), .indeterminate)
    }

    /// The expensive failure mode is demoting a real job, so an unrecognised city is not guessed at.
    func testUnrecognisedPlacesAreNotGuessed() {
        XCTAssertEqual(classify("Ontario"), .indeterminate, "Ontario is also a California city")
        XCTAssertEqual(classify("Springfield"), .indeterminate)
    }

    /// Substring matching would make "Austria" contain "us" and "Indiana" contain "india".
    func testWordBoundariesPreventLookalikeMatches() {
        XCTAssertEqual(classify("Austria"), .outOfBounds, "must not be read as a US token")
        XCTAssertEqual(classify("Indianapolis, Indiana"), .eligible, "must not be read as India")
    }

    // MARK: - Integration with the criteria verdict

    private func meets(_ location: String?, preferred: String = "United States") -> Bool {
        LocationCriteria.meets(
            remoteType: .remote, location: location, preferredLocations: preferred,
            allowRemote: true, allowHybrid: false, allowOnsite: false, filterEnabled: true
        )
    }

    func testCriteriaVerdictFollowsGeography() {
        XCTAssertFalse(meets("Amsterdam"), "job #341 must now read as outside criteria")
        XCTAssertTrue(meets("Remote, US"))
        XCTAssertTrue(meets("Global"), "no signal must not demote the job")
    }

    /// Parity guard: with no preferred locations configured there is nothing to judge against, so the
    /// original remote-mode-only behaviour must be untouched.
    func testNoPreferredLocationsLeavesRemoteUngated() {
        XCTAssertTrue(meets("Amsterdam", preferred: ""))
    }

    func testAllowRemoteOffStillWins() {
        XCTAssertFalse(LocationCriteria.meets(
            remoteType: .remote, location: "Remote, US", preferredLocations: "United States",
            allowRemote: false, allowHybrid: true, allowOnsite: true, filterEnabled: true
        ))
    }
}
