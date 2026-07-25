import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-630/644: referral summary derivation, 4-state lifecycle dates, duplicate-recipient detection.
final class ReferralTrackingTests: XCTestCase {
    private func attempt(
        _ outcome: ReferralOutcome, name: String = "Jane", identifier: String? = nil
    ) -> ReferralTracking.Attempt {
        .init(outcome: outcome, recipientName: name, recipientIdentifier: identifier, requestedAt: Date())
    }

    func testNeedsOutreachOnlyWhenAppliedWithoutAttempts() {
        // Apply-first workflow (TASK-644 review): the nudge is Applied-only — Interested isn't nudged
        // (list-view noise) and Interview/Offer aren't either (already in the system).
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: []), .needsOutreach)
        for status in ["pursuing", "interview", "offer", "new", "archived", "closed", "rejected"] {
            XCTAssertEqual(ReferralTracking.summary(jobStatus: status, attempts: []), ReferralSummary.none, status)
        }
    }

    func testOutcomePrecedenceSubmittedOverRespondedOverRequestedOverDeclined() {
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.requested)]), .requested)
        XCTAssertEqual(
            ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.requested), attempt(.responded)]),
            .responded, "responded beats requested"
        )
        XCTAssertEqual(
            ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.responded), attempt(.submitted)]),
            .submitted, "submitted beats responded"
        )
        // An all-declined job still *in* the outreach funnel needs fresh outreach rather than going
        // quiet — see `testAllDeclinedOnAppliedJobNeedsFreshOutreach` (TASK-644 review).
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "archived", attempts: [attempt(.declined)]), .declined)
        XCTAssertEqual(
            ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.declined), attempt(.submitted)]),
            .submitted, "submitted wins over a prior decline"
        )
    }

    func testNotApplicableMarkerIsOverriddenByRealRequest() {
        let marker = ReferralTracking.Attempt(
            outcome: .notApplicable, recipientName: "", recipientIdentifier: nil, requestedAt: Date()
        )
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: [marker]), .notApplicable)
        XCTAssertEqual(
            ReferralTracking.summary(jobStatus: "applied", attempts: [marker, attempt(.requested)]),
            .requested, "a real request supersedes the N/A marker"
        )
    }

    func testLeavingFunnelKeepsAttemptSummaryButNotNeedsOutreach() {
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "archived", attempts: [attempt(.requested)]), .requested)
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "archived", attempts: []), .none)
    }

    // MARK: - Per-state dates (TASK-644)

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var now: Date {
        Date(timeIntervalSince1970: 2_000_000)
    }

    func testNormalizedDatesStampsReachedStateAndClearsLater() {
        let responded = ReferralTracking.normalizedDates(
            outcome: .responded, dates: .init(requested: t0), now: now
        )
        XCTAssertEqual(responded.requested, t0)
        XCTAssertEqual(responded.responded, now)
        XCTAssertNil(responded.submitted)
        XCTAssertNil(responded.declined)
    }

    func testNormalizedDatesRevertClearsLaterDates() {
        // A fully-submitted request reverted to requested drops responded + submitted (the mistake case).
        let full = ReferralTracking.StateDates(requested: t0, responded: now, submitted: now, declined: nil)
        let reverted = ReferralTracking.normalizedDates(outcome: .requested, dates: full, now: now)
        XCTAssertEqual(reverted.requested, t0)
        XCTAssertNil(reverted.responded)
        XCTAssertNil(reverted.submitted)
        XCTAssertNil(reverted.declined)
    }

    func testNormalizedDatesSubmittedAndDeclinedAreMutuallyExclusive() {
        let dates = ReferralTracking.StateDates(requested: t0, responded: t0, submitted: now, declined: nil)
        let declined = ReferralTracking.normalizedDates(outcome: .declined, dates: dates, now: now)
        XCTAssertEqual(declined.responded, t0, "responded may precede a decline and is kept")
        XCTAssertNil(declined.submitted, "a declined request was not submitted")
        XCTAssertEqual(declined.declined, now)
    }

    func testNormalizedDatesPreservesExistingDatesWithoutRestamping() {
        let existing = ReferralTracking.StateDates(requested: t0, responded: t0, submitted: nil, declined: nil)
        let same = ReferralTracking.normalizedDates(outcome: .responded, dates: existing, now: now)
        XCTAssertEqual(same.responded, t0, "an already-set responded date is not overwritten with now")
    }

    func testStateDateReturnsCurrentStateDate() {
        let dates = ReferralTracking.StateDates(requested: t0, responded: now, submitted: nil, declined: nil)
        XCTAssertEqual(ReferralTracking.stateDate(outcome: .requested, dates: dates), t0)
        XCTAssertEqual(ReferralTracking.stateDate(outcome: .responded, dates: dates), now)
        XCTAssertEqual(ReferralTracking.stateDate(outcome: .submitted, dates: dates), t0, "falls back to ask date")
    }

    // MARK: - Follow-up nudges (TASK-644 Phase 2)

    private func dated(_ outcome: ReferralOutcome, requested: Date, responded: Date? = nil) -> ReferralTracking
        .Attempt {
        .init(
            outcome: outcome,
            recipientName: "Jane",
            recipientIdentifier: nil,
            requestedAt: requested,
            respondedAt: responded
        )
    }

    func testFollowUpAwaitingResponseAfterGrace() {
        let old = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 5 * 86400) // 5 days later, grace = 4
        let nudge = ReferralTracking.followUp(attempts: [dated(.requested, requested: old)], now: now)
        XCTAssertEqual(nudge?.kind, .awaitingResponse)
        XCTAssertEqual(nudge?.since, old)
    }

    func testFollowUpNotYetDueWithinGrace() {
        let recent = Date(timeIntervalSince1970: 2 * 86400)
        let now = Date(timeIntervalSince1970: 5 * 86400) // 3 days after request < 4-day grace
        XCTAssertNil(ReferralTracking.followUp(attempts: [dated(.requested, requested: recent)], now: now))
    }

    func testFollowUpAwaitingSubmissionCountsFromResponse() {
        let requested = Date(timeIntervalSince1970: 0)
        let responded = Date(timeIntervalSince1970: 1 * 86400)
        let now = Date(timeIntervalSince1970: 9 * 86400) // 8 days after response, grace = 7
        let nudge = ReferralTracking.followUp(
            attempts: [dated(.responded, requested: requested, responded: responded)], now: now
        )
        XCTAssertEqual(nudge?.kind, .awaitingSubmission)
        XCTAssertEqual(nudge?.since, responded)
    }

    func testFollowUpNoneWhenSubmittedOrDeclinedOrNA() {
        let old = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 30 * 86400)
        XCTAssertNil(ReferralTracking.followUp(attempts: [dated(.submitted, requested: old)], now: now))
        XCTAssertNil(ReferralTracking.followUp(attempts: [dated(.declined, requested: old)], now: now))
        XCTAssertNil(ReferralTracking.followUp(attempts: [dated(.notApplicable, requested: old)], now: now))
        XCTAssertNil(ReferralTracking.followUp(attempts: [], now: now))
    }

    func testFollowUpRespondedSupersedesAStaleRequestToAnotherContact() {
        // One contact asked long ago (would be stale) but another responded recently → wait on them.
        let old = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 10 * 86400)
        let recentResponse = Date(timeIntervalSince1970: 9 * 86400) // 1 day ago < 7-day grace
        let attempts = [
            dated(.requested, requested: old),
            dated(.responded, requested: old, responded: recentResponse)
        ]
        XCTAssertNil(ReferralTracking.followUp(attempts: attempts, now: now), "recent response supersedes; no nudge")
    }

    // MARK: - Backward-compatible raw values

    func testLegacyRawValuesStillDecode() {
        XCTAssertEqual(ReferralOutcome(rawValue: "referred"), .submitted)
        XCTAssertEqual(ReferralOutcome(rawValue: "not_pursuing"), .notApplicable)
    }

    // MARK: - Duplicate detection

    func testDuplicateRecipientByIdentifierIsCaseInsensitive() {
        let existing = [attempt(.requested, name: "Jane Doe", identifier: "https://linkedin.com/in/jane")]
        XCTAssertNotNil(
            ReferralTracking.duplicateAttempt(
                name: "Someone Else", identifier: "https://LinkedIn.com/in/JANE", among: existing
            ),
            "same identifier (different case) is a duplicate regardless of name"
        )
    }

    func testDuplicateRecipientByNormalizedNameWhenNoIdentifier() {
        let existing = [attempt(.requested, name: "Jane  Doe")]
        XCTAssertNotNil(ReferralTracking.duplicateAttempt(name: "jane doe", identifier: nil, among: existing))
        XCTAssertNil(ReferralTracking.duplicateAttempt(name: "John Smith", identifier: nil, among: existing))
    }

    func testDuplicateIgnoresNotApplicableMarkersAndEmptyKeys() {
        let marker = ReferralTracking.Attempt(
            outcome: .notApplicable, recipientName: "", recipientIdentifier: nil, requestedAt: Date()
        )
        XCTAssertNil(ReferralTracking.duplicateAttempt(name: "", identifier: nil, among: [marker]))
        XCTAssertNil(ReferralTracking.duplicateAttempt(name: "Jane", identifier: nil, among: [marker]))
    }

    // MARK: - Recipient key normalization (TASK-644 review)

    /// The same LinkedIn profile written the many ways a user might paste it must collide.
    func testIdentifierNormalizationCollapsesURLVariants() {
        let canonical = "linkedin.com/in/jane"
        for variant in [
            "linkedin.com/in/jane",
            "https://www.linkedin.com/in/jane/",
            "http://linkedin.com/in/jane",
            "https://www.linkedin.com/in/jane?originalSubdomain=uk",
            "  HTTPS://WWW.LinkedIn.com/in/Jane/  "
        ] {
            XCTAssertEqual(ReferralTracking.normalizedIdentifier(variant), canonical, variant)
        }
    }

    /// The bug this fixes: a contact saved with a URL wasn't recognized when re-entered by name alone,
    /// because the key was *either* the identifier *or* the name — never both.
    func testDuplicateMatchesIdentifierRecordByNameAlone() {
        let prior = attempt(.requested, name: "Jane Doe", identifier: "https://www.linkedin.com/in/jane/")
        XCTAssertNotNil(ReferralTracking.duplicateAttempt(name: "Jane Doe", identifier: nil, among: [prior]))
        XCTAssertNotNil(
            ReferralTracking.duplicateAttempt(name: "", identifier: "linkedin.com/in/jane", among: [prior])
        )
        XCTAssertNil(ReferralTracking.duplicateAttempt(name: "Bob", identifier: nil, among: [prior]))
    }

    func testRecipientKeysIgnoresEmptyComponents() {
        XCTAssertTrue(ReferralTracking.recipientKeys(name: "  ", identifier: nil).isEmpty)
        XCTAssertEqual(ReferralTracking.recipientKeys(name: "Jane Doe", identifier: nil), ["jane doe"])
    }

    // MARK: - All-declined re-nudges an in-funnel job (TASK-644 review)

    func testAllDeclinedOnAppliedJobNeedsFreshOutreach() {
        let declined = [attempt(.declined, name: "Jane"), attempt(.declined, name: "Bob")]
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: declined), .needsOutreach)
        // Off the outreach funnel it just reads as declined — no nudge for a job you're not pursuing.
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "archived", attempts: declined), .declined)
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "interview", attempts: declined), .declined)
    }

    func testActiveRequestStillWinsOverDeclined() {
        let mixed = [attempt(.declined, name: "Jane"), attempt(.requested, name: "Bob")]
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: mixed), .requested)
    }

    // MARK: - Follow-up grace boundaries

    func testFollowUpGraceBoundariesAreInclusive() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        func requested(daysAgo: Double) -> [ReferralTracking.Attempt] {
            [.init(
                outcome: .requested, recipientName: "Jane", recipientIdentifier: nil,
                requestedAt: now.addingTimeInterval(-daysAgo * 86400)
            )]
        }
        XCTAssertNotNil(ReferralTracking.followUp(attempts: requested(daysAgo: 4), now: now))
        XCTAssertNil(ReferralTracking.followUp(attempts: requested(daysAgo: 3.99), now: now))
    }

    /// A declined request must not suppress the nudge for a still-open one.
    func testDeclinedDoesNotSuppressAwaitingResponse() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let old = now.addingTimeInterval(-10 * 86400)
        let attempts: [ReferralTracking.Attempt] = [
            .init(outcome: .declined, recipientName: "Bob", recipientIdentifier: nil, requestedAt: old),
            .init(outcome: .requested, recipientName: "Jane", recipientIdentifier: nil, requestedAt: old)
        ]
        XCTAssertEqual(ReferralTracking.followUp(attempts: attempts, now: now)?.kind, .awaitingResponse)
    }
}
