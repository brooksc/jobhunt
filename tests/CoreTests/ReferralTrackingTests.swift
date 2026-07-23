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

    func testNeedsOutreachOnlyInsideTheFunnelWithoutAttempts() {
        for status in ["applied", "interview", "offer"] {
            XCTAssertEqual(ReferralTracking.summary(jobStatus: status, attempts: []), .needsOutreach, status)
        }
        for status in ["pursuing", "new", "archived", "closed", "rejected"] {
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
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.declined)]), .declined)
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
    private var now: Date { Date(timeIntervalSince1970: 2_000_000) }

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
}
