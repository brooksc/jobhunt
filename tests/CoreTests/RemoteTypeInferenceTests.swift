import XCTest
@testable import JobhuntCore

/// Job #525 (The Hartford) had location "United States - Remote" with a null `remoteType`, so it read
/// as "Arrangement not stated", matched the *Unknown* filter rather than *Remote*, and — since a null
/// arrangement falls to the on-site branch — was judged as failing the location criteria.
final class RemoteTypeInferenceTests: XCTestCase {
    private func infer(_ location: String?, existing: RemoteType? = nil) -> RemoteType? {
        RemoteTypeInference.infer(remoteType: existing, location: location)
    }

    // MARK: - Fills a missing arrangement

    func testReportedCaseIsInferred() {
        XCTAssertEqual(infer("United States - Remote"), .remote)
    }

    func testRemoteLocationsAreRecognisedAcrossFormats() {
        for location in [
            "Remote",
            "US-CA-Remote",
            "US Remote (Preferred location Michigan)",
            "Remote within the United States or Austin, Texas",
            "REMOTE"
        ] {
            XCTAssertEqual(infer(location), .remote, location)
        }
    }

    /// `.unknown` is as much a "we don't know" as nil, so both get filled.
    func testUnknownIsTreatedAsMissing() {
        XCTAssertEqual(infer("Remote", existing: .unknown), .remote)
    }

    // MARK: - Never overrides a real answer

    func testExplicitArrangementsAreLeftAlone() {
        XCTAssertEqual(infer("Remote", existing: .onsite), .onsite)
        XCTAssertEqual(infer("Remote", existing: .hybrid), .hybrid)
        XCTAssertEqual(infer("Austin, TX", existing: .remote), .remote)
    }

    // MARK: - Ambiguity resolves toward remote (deliberate)

    /// A posting offering a *choice* of arrangements does offer remote, so it counts. Surfacing a
    /// hybrid role in the Remote filter costs one archive click; hiding a real remote job under
    /// "Unknown" costs the opportunity. Both strings are real rows from the library.
    func testMultiArrangementPostingsCountAsRemote() {
        XCTAssertEqual(infer("REMOTE/SF-HYBRID"), .remote)
        XCTAssertEqual(infer("Remote, hybrid, or in-office (Columbus, OH)"), .remote)
        XCTAssertEqual(infer("Remote or on-site in Denver"), .remote)
        XCTAssertEqual(infer("Hybrid remote"), .remote)
    }

    func testNegatedRemoteIsNotInferred() {
        XCTAssertNil(infer("Chicago, IL (not remote)"))
        XCTAssertNil(infer("No remote work"))
    }

    func testLocationsWithoutRemoteAreUntouched() {
        XCTAssertNil(infer("Austin, TX"))
        XCTAssertNil(infer(""))
        XCTAssertNil(infer(nil))
    }

    // MARK: - The downstream effects that motivated this

    /// The criteria verdict was the real damage: a null arrangement is judged as on-site.
    func testInferredRemoteNowMeetsCriteria() {
        let location = "United States - Remote"
        func meets(_ type: RemoteType?) -> Bool {
            LocationCriteria.meets(
                remoteType: type, location: location, preferredLocations: "United States",
                allowRemote: true, allowHybrid: false, allowOnsite: false, filterEnabled: true
            )
        }
        XCTAssertFalse(meets(nil), "the old behaviour: judged as on-site")
        XCTAssertTrue(meets(infer(location)), "with the arrangement filled in it qualifies")
    }

    /// And the filter: it now lands in Remote instead of Unknown.
    func testInferredJobMatchesTheRemoteFilter() {
        let inferred = infer("United States - Remote")
        XCTAssertTrue(JobFilterRules.matchesRemote(inferred, selected: [.remote]))
        XCTAssertFalse(JobFilterRules.matchesRemote(inferred, selected: [.unknown]))
    }
}
