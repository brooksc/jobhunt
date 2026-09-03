import XCTest
@testable import JobhuntCore

/// TASK-464: the deterministic meets_criteria computation. These cases pin the verdict for each
/// arrangement/settings combination, so a change to the matching rules can't quietly reclassify
/// the jobs already in the library.
final class LocationCriteriaTests: XCTestCase {
    private func meets(
        _ remote: RemoteType?, location: String? = nil, preferred: String? = nil,
        allowRemote: Bool = true, allowHybrid: Bool = true, allowOnsite: Bool = true,
        enabled: Bool = true
    ) -> Bool {
        LocationCriteria.meets(
            remoteType: remote, location: location, preferredLocations: preferred,
            allowRemote: allowRemote, allowHybrid: allowHybrid, allowOnsite: allowOnsite,
            filterEnabled: enabled
        )
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

/// Remote eligibility is a different question from preferred locations: "where can I legally work
/// remotely" versus "where would I commute to". They shared one field, so a Seattle-based user could
/// not say "remote anywhere in the US" without also implying they'd only commute to the US — and a
/// non-US user could not say anything at all, because eligibility fell back to hardcoded US tokens.
final class RemoteEligibilityRegionTests: XCTestCase {
    private func meets(
        location: String?,
        preferred: String = "Seattle, WA",
        eligibility: String? = nil
    ) -> Bool {
        LocationCriteria.meets(
            remoteType: .remote,
            location: location,
            preferredLocations: preferred,
            remoteEligibilityRegions: eligibility,
            allowRemote: true, allowHybrid: true, allowOnsite: true, filterEnabled: true
        )
    }

    /// #1 — a remote role whose geography excludes the user must not read as meeting criteria.
    func testExplicitRegionRulesOutAForeignRemoteRole() {
        XCTAssertFalse(meets(location: "Remote - Colombia", eligibility: "United States"))
        XCTAssertFalse(meets(location: "Remote (Europe)", eligibility: "United States"))
    }

    /// #2 — the common case must not regress into a false negative.
    func testBareRemoteStillPasses() {
        XCTAssertTrue(meets(location: "Remote", eligibility: "United States"))
        XCTAssertTrue(meets(location: nil, eligibility: "United States"))
        XCTAssertTrue(meets(location: "Global", eligibility: "United States"))
    }

    /// #3 — the setting works on its own terms, independent of where the user would commute.
    func testEligibilityIsNotConflatedWithCommutingPreference() {
        // Commutes only to Seattle, but can work remotely anywhere in Canada.
        XCTAssertTrue(meets(location: "Remote - Toronto, Canada", preferred: "Seattle, WA", eligibility: "Canada"))
        // And a US-only remote role is now out of bounds for that same user.
        XCTAssertFalse(meets(location: "Remote - United States", preferred: "Seattle, WA", eligibility: "Canada"))
    }

    /// A remote posting carrying an unrelated HQ city is not a geography claim.
    func testUnrelatedHQCityDoesNotRuleOut() {
        XCTAssertTrue(meets(location: "Remote", preferred: "Seattle, WA", eligibility: "United States"))
    }

    /// Empty setting keeps the previous behaviour exactly: preferred terms, then the US fallback.
    func testEmptySettingFallsBackToPreviousBehaviour() {
        XCTAssertTrue(meets(location: "Remote - US", eligibility: ""))
        XCTAssertTrue(meets(location: "Remote - Seattle, WA", eligibility: nil))
        XCTAssertFalse(meets(location: "Remote - Colombia", eligibility: nil))
    }

    /// It applies even when no commuting preference is set at all — that path used to return early.
    func testAppliesWithNoPreferredLocations() {
        XCTAssertFalse(meets(location: "Remote - Colombia", preferred: "", eligibility: "United States"))
        XCTAssertTrue(meets(location: "Remote", preferred: "", eligibility: "United States"))
    }

    /// #4 — hybrid and onsite are untouched by any of this.
    func testHybridAndOnsiteUnchanged() {
        for mode in [RemoteType.hybrid, .onsite] {
            XCTAssertTrue(LocationCriteria.meets(
                remoteType: mode, location: "Seattle, WA", preferredLocations: "Seattle, WA",
                remoteEligibilityRegions: "Canada",
                allowRemote: true, allowHybrid: true, allowOnsite: true, filterEnabled: true
            ), "\(mode) must still gate on preferred locations, not remote eligibility")
        }
    }
}

/// Two-letter state abbreviations used to be matched as whole words, so ordinary English in a
/// location string satisfied the US check and the foreign check below it never ran. "Remote in
/// Europe" read as eligible via Indiana, "LATAM or EMEA" via Oregon, "Rio de Janeiro" via Delaware —
/// silently defeating the geography filter these tests exist to protect.
final class RemoteGeographyStopwordTests: XCTestCase {
    /// The three strings observed misclassifying, plus the connector words most likely to recur.
    func testConnectorWordsAreNotUSStateSignals() {
        let foreignOnly = [
            "Remote — Rio de Janeiro",
            "Remote in Europe",
            "Remote — LATAM or EMEA",
            "Anywhere in the EU",
            "Remote - Berlin or Munich",
            "Ciudad de México"
        ]
        for location in foreignOnly {
            XCTAssertEqual(
                RemoteGeography.classify(location: location, preferredTerms: []),
                .outOfBounds,
                "\(location) names only foreign places"
            )
        }
    }

    /// The abbreviations must not leak back in through the user's own preferred locations either:
    /// `parsePreferredLocations` expands "CO" to ["CO", "Colorado"], so the bare form is redundant.
    func testRedundantStateAbbreviationInPreferredTermsDoesNotMatchProse() {
        XCTAssertEqual(
            RemoteGeography.classify(
                location: "Remote in Europe", preferredTerms: ["CO", "Colorado"]
            ),
            .outOfBounds
        )
        // A two-letter term the user supplied that ISN'T a redundant state abbreviation still counts.
        XCTAssertEqual(
            RemoteGeography.classify(location: "Remote - UK", preferredTerms: ["UK"]),
            .eligible
        )
    }

    /// Dropping the abbreviations must not turn genuine US postings into foreign ones: they either
    /// still match on a real place name, or fall to `.indeterminate`, which callers treat as passing.
    func testUSPostingsAreStillNotRuledOut() {
        for location in ["Remote - US", "Remote — Austin, TX", "Remote (Seattle, WA)", "Remote - TX"] {
            XCTAssertNotEqual(
                RemoteGeography.classify(location: location, preferredTerms: []),
                .outOfBounds,
                "\(location) must never read as out of bounds"
            )
        }
        XCTAssertEqual(
            RemoteGeography.classify(location: "Remote — Austin, TX", preferredTerms: []),
            .eligible
        )
    }

    /// Accented spellings must classify the same as their ASCII forms. `normalizeForMatch` turns an
    /// accented letter into a space, splitting the word ("México" → "m xico"), so every accented
    /// place in the token list was unreachable from a posting that spelled it correctly.
    func testAccentedPlaceNamesAreRecognised() {
        for location in [
            "Ciudad de México",
            "Remote — São Paulo",
            "Remote - Bogotá",
            "Medellín, Colombia",
            "Remote (Kraków)",
            "Zürich, Switzerland"
        ] {
            XCTAssertEqual(
                RemoteGeography.classify(location: location, preferredTerms: []),
                .outOfBounds,
                "\(location) is a foreign place however it is spelled"
            )
        }
    }

    /// End to end through the filter: the bug's user-visible shape was a Europe-only role sitting in
    /// the list looking qualified.
    func testFilterRulesOutEuropeOnlyRemoteRole() {
        XCTAssertFalse(LocationCriteria.meets(
            remoteType: .remote,
            location: "Remote in Europe",
            preferredLocations: "Seattle, WA",
            allowRemote: true, allowHybrid: true, allowOnsite: true, filterEnabled: true
        ))
    }
}
