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

    // MARK: - Location criteria buckets

    func testCriteriaAnyMatchesEverything() {
        for stored: Bool? in [true, false, nil] {
            XCTAssertTrue(JobFilterRules.matchesCriteria(
                meetsCriteria: stored, remoteType: .remote, wanted: nil
            ))
        }
    }

    func testMeetsBucket() {
        XCTAssertEqual(
            JobFilterRules.criteriaBucket(meetsCriteria: true, remoteType: .remote), .meets
        )
    }

    /// The job-443 case: extraction succeeded but the posting states no location or arrangement.
    /// LocationCriteria scores that as onsite, so it's stored `false` — but calling it a confirmed
    /// rejection is wrong. It must land in its own bucket.
    func testSilentPostingIsNotStatedRatherThanRejected() {
        for type: RemoteType? in [.unknown, nil] {
            XCTAssertEqual(
                JobFilterRules.criteriaBucket(meetsCriteria: false, remoteType: type), .notStated,
                String(describing: type)
            )
            XCTAssertFalse(
                JobFilterRules.matchesCriteria(meetsCriteria: false, remoteType: type, wanted: .doesNotMeet),
                "a silent posting must not appear under Doesn't meet"
            )
            XCTAssertTrue(
                JobFilterRules.matchesCriteria(meetsCriteria: false, remoteType: type, wanted: .notStated)
            )
        }
    }

    /// A posting that actually states an arrangement the user disallows is a real rejection.
    func testStatedArrangementIsARealRejection() {
        for type in [RemoteType.onsite, .hybrid] {
            XCTAssertEqual(
                JobFilterRules.criteriaBucket(meetsCriteria: false, remoteType: type), .doesNotMeet,
                type.rawValue
            )
        }
    }

    /// A job whose verdict was never computed (extraction failed) belongs to no bucket.
    func testUncomputedVerdictMatchesNoBucket() {
        XCTAssertNil(JobFilterRules.criteriaBucket(meetsCriteria: nil, remoteType: .unknown))
        for wanted in JobFilterRules.CriteriaBucket.allCases {
            XCTAssertFalse(JobFilterRules.matchesCriteria(
                meetsCriteria: nil, remoteType: .unknown, wanted: wanted
            ))
        }
    }

    // MARK: - The live triage case

    /// End-to-end: with onsite disallowed, a silent posting is stored as not meeting criteria and is
    /// reachable only under "Not stated" — so it can be reviewed without being labelled a rejection.
    func testUnknownRemoteTypeIsReviewableWithoutBeingCalledARejection() {
        let meets = LocationCriteria.meets(
            remoteType: .unknown, location: nil, preferredLocations: "",
            allowRemote: true, allowHybrid: false, allowOnsite: false, filterEnabled: true
        )
        XCTAssertFalse(meets)
        XCTAssertEqual(
            JobFilterRules.criteriaBucket(meetsCriteria: meets, remoteType: .unknown), .notStated
        )
        // A genuinely remote job still passes.
        let remoteMeets = LocationCriteria.meets(
            remoteType: .remote, location: "Remote - USA", preferredLocations: "",
            allowRemote: true, allowHybrid: false, allowOnsite: false, filterEnabled: true
        )
        XCTAssertEqual(
            JobFilterRules.criteriaBucket(meetsCriteria: remoteMeets, remoteType: .remote), .meets
        )
    }

    // MARK: - Data quality

    func testQualityAnyMatchesEverything() {
        XCTAssertTrue(JobFilterRules.matchesQuality(kinds: [], wanted: nil))
        XCTAssertTrue(JobFilterRules.matchesQuality(kinds: [.missingSalary], wanted: nil))
    }

    func testHasIssuesMatchesAnyIssueButNotACleanJob() {
        XCTAssertFalse(JobFilterRules.matchesQuality(kinds: [], wanted: .hasIssues))
        XCTAssertTrue(JobFilterRules.matchesQuality(kinds: [.missingSalary], wanted: .hasIssues))
    }

    /// High severity is the re-sourcing shortlist: a missing salary isn't worth hunting down the
    /// original posting for, a missing company is.
    func testHighSeverityExcludesLowSeverityOnlyJobs() {
        XCTAssertFalse(
            JobFilterRules.matchesQuality(kinds: [.missingSalary, .staleExtraction], wanted: .highSeverity)
        )
        for kind in [QualityIssueKind.missingCompany, .missingTitle, .missingLocation, .extractionFailed] {
            XCTAssertTrue(
                JobFilterRules.matchesQuality(kinds: [kind, .missingSalary], wanted: .highSeverity),
                kind.rawValue
            )
        }
    }

    /// A high-severity job is necessarily also matched by the broader "any issue" filter.
    func testHighSeverityIsASubsetOfHasIssues() {
        let kinds: [QualityIssueKind] = [.missingCompany]
        XCTAssertTrue(JobFilterRules.matchesQuality(kinds: kinds, wanted: .highSeverity))
        XCTAssertTrue(JobFilterRules.matchesQuality(kinds: kinds, wanted: .hasIssues))
    }

    // MARK: - Source

    func testNilSourceSelectionMatchesEverything() {
        XCTAssertTrue(JobFilterRules.matchesSource(host: "linkedin.com", selected: nil))
        XCTAssertTrue(JobFilterRules.matchesSource(host: nil, selected: nil))
    }

    func testSourceSelectionMatchesOnlyChosenHosts() {
        let selected: Set = ["linkedin.com"]
        XCTAssertTrue(JobFilterRules.matchesSource(host: "linkedin.com", selected: selected))
        XCTAssertFalse(JobFilterRules.matchesSource(host: "job-boards.greenhouse.io", selected: selected))
    }

    /// A job with no capture (so no host) belongs to no named source.
    func testHostlessJobIsExcludedWhenASourceIsChosen() {
        XCTAssertFalse(JobFilterRules.matchesSource(host: nil, selected: ["linkedin.com"]))
    }

    func testMultipleSourcesAreUnioned() {
        let selected: Set = ["linkedin.com", "jobs.ashbyhq.com"]
        XCTAssertTrue(JobFilterRules.matchesSource(host: "jobs.ashbyhq.com", selected: selected))
        XCTAssertFalse(JobFilterRules.matchesSource(host: "jobs.lever.co", selected: selected))
    }

    // MARK: - Fit score, including never-scored

    func testFitScoreMinimumTreatsAbsentScoreAsFailing() {
        XCTAssertTrue(JobFilterRules.matchesFitScore(fitScore: 80, minimum: 70, unscoredOnly: false))
        XCTAssertFalse(JobFilterRules.matchesFitScore(fitScore: 60, minimum: 70, unscoredOnly: false))
        XCTAssertFalse(JobFilterRules.matchesFitScore(fitScore: nil, minimum: 70, unscoredOnly: false))
    }

    func testNoFilterMatchesEverything() {
        XCTAssertTrue(JobFilterRules.matchesFitScore(fitScore: nil, minimum: nil, unscoredOnly: false))
        XCTAssertTrue(JobFilterRules.matchesFitScore(fitScore: 42, minimum: nil, unscoredOnly: false))
    }

    /// The gap this closes: an unscored job is excluded by every threshold, so without a dedicated
    /// option those jobs are unreachable by any fit filter.
    func testUnscoredOnlySelectsExactlyTheNeverScored() {
        XCTAssertTrue(JobFilterRules.matchesFitScore(fitScore: nil, minimum: nil, unscoredOnly: true))
        XCTAssertFalse(JobFilterRules.matchesFitScore(fitScore: 0, minimum: nil, unscoredOnly: true))
        XCTAssertFalse(JobFilterRules.matchesFitScore(fitScore: 90, minimum: nil, unscoredOnly: true))
    }

    /// A zero score is a real judgement, not an absent one — they must not be conflated.
    func testZeroScoreIsNotTreatedAsUnscored() {
        XCTAssertFalse(JobFilterRules.matchesFitScore(fitScore: 0, minimum: nil, unscoredOnly: true))
        XCTAssertTrue(JobFilterRules.matchesFitScore(fitScore: 0, minimum: 0, unscoredOnly: false))
    }
}
