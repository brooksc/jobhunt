import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-630: referral summary derivation + duplicate-recipient detection.
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

    func testOutcomePrecedenceReferredOverRequestedOverDeclined() {
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.requested)]), .requested)
        XCTAssertEqual(
            ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.requested), attempt(.referred)]),
            .referred, "referred wins"
        )
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.declined)]), .declined)
        XCTAssertEqual(
            ReferralTracking.summary(jobStatus: "applied", attempts: [attempt(.declined), attempt(.referred)]),
            .referred, "referred wins over a prior decline"
        )
    }

    func testNotPursuingMarkerIsOverriddenByRealAttempt() {
        let marker = ReferralTracking.Attempt(outcome: .notPursuing, recipientName: "", recipientIdentifier: nil, requestedAt: Date())
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "applied", attempts: [marker]), .notPursuing)
        XCTAssertEqual(
            ReferralTracking.summary(jobStatus: "applied", attempts: [marker, attempt(.requested)]),
            .requested, "a real attempt supersedes the not-pursuing marker"
        )
    }

    func testLeavingFunnelKeepsAttemptSummaryButNotNeedsOutreach() {
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "archived", attempts: [attempt(.requested)]), .requested)
        XCTAssertEqual(ReferralTracking.summary(jobStatus: "archived", attempts: []), .none)
    }

    func testDuplicateRecipientByIdentifierIsCaseInsensitive() {
        let existing = [attempt(.requested, name: "Jane Doe", identifier: "https://linkedin.com/in/jane")]
        XCTAssertNotNil(
            ReferralTracking.duplicateAttempt(name: "Someone Else", identifier: "https://LinkedIn.com/in/JANE", among: existing),
            "same identifier (different case) is a duplicate regardless of name"
        )
    }

    func testDuplicateRecipientByNormalizedNameWhenNoIdentifier() {
        let existing = [attempt(.requested, name: "Jane  Doe")]
        XCTAssertNotNil(ReferralTracking.duplicateAttempt(name: "jane doe", identifier: nil, among: existing))
        XCTAssertNil(ReferralTracking.duplicateAttempt(name: "John Smith", identifier: nil, among: existing))
    }

    func testDuplicateIgnoresNotPursuingMarkersAndEmptyKeys() {
        let marker = ReferralTracking.Attempt(outcome: .notPursuing, recipientName: "", recipientIdentifier: nil, requestedAt: Date())
        XCTAssertNil(ReferralTracking.duplicateAttempt(name: "", identifier: nil, among: [marker]))
        XCTAssertNil(ReferralTracking.duplicateAttempt(name: "Jane", identifier: nil, among: [marker]))
    }
}
