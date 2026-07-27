import Foundation
import XCTest
@testable import JobhuntCore

/// "Which of this company's postings is the better bet?" — the ranking and matching behind the
/// one-line company context above the pay range.
final class CompanyContextTests: XCTestCase {
    private func role(
        _ id: String, _ title: String, _ status: JobStatus, fit: Int? = nil
    ) -> CompanyContext.Role {
        .init(jobID: id, jobNumber: nil, title: title, status: status, fitScore: fit)
    }

    private func build(
        viewed: CompanyContext.Role, company: String?, others: [(CompanyContext.Role, String?)]
    ) -> CompanyContext.Result {
        CompanyContext.build(viewed: viewed, company: company, among: others.map { (role: $0.0, company: $0.1) })
    }

    // MARK: - Matching

    func testOnlySameCompanyRolesAreIncluded() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Stripe",
            others: [
                (role("b", "Staff TPM", .new, fit: 90), "Stripe"),
                (role("c", "Other TPM", .new, fit: 95), "Block")
            ]
        )
        XCTAssertEqual(result.openRoles.map(\.jobID), ["b"])
    }

    /// Extracted company names vary in case — the store holds both "Twilio" and "twilio".
    func testCompanyMatchingIsCaseAndWhitespaceInsensitive() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Twilio",
            others: [(role("b", "Staff TPM", .new, fit: 80), "  twilio ")]
        )
        XCTAssertEqual(result.openRoles.map(\.jobID), ["b"])
    }

    /// Conservative on purpose: wrongly merging two companies is worse than missing a match.
    func testDifferentlyNamedCompaniesAreNotMerged() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Vertex",
            others: [(role("b", "Staff TPM", .new, fit: 80), "Vertex Inc")]
        )
        XCTAssertTrue(result.openRoles.isEmpty)
    }

    func testViewedJobIsNeverListedAgainstItself() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Stripe",
            others: [(role("a", "TPM", .pursuing), "Stripe")]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testMissingCompanyYieldsNothing() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: nil,
            others: [(role("b", "Staff TPM", .new, fit: 90), nil)]
        )
        XCTAssertTrue(result.isEmpty, "blank company must not group every unextracted job together")
    }

    // MARK: - What counts as an alternative

    func testOnlyNewAndInterestedCountAsOpen() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Stripe",
            others: [
                (role("b", "Open A", .new, fit: 70), "Stripe"),
                (role("c", "Open B", .pursuing, fit: 80), "Stripe"),
                (role("d", "Applied", .applied, fit: 99), "Stripe"),
                (role("e", "Archived", .archived, fit: 99), "Stripe")
            ]
        )
        XCTAssertEqual(Set(result.openRoles.map(\.jobID)), ["b", "c"])
    }

    // MARK: - Ranking

    func testOpenRolesAreRankedByFitDescending() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Stripe",
            others: [
                (role("low", "C", .new, fit: 62), "Stripe"),
                (role("high", "A", .new, fit: 92), "Stripe"),
                (role("mid", "B", .new, fit: 78), "Stripe")
            ]
        )
        XCTAssertEqual(result.openRoles.map(\.jobID), ["high", "mid", "low"])
        XCTAssertEqual(result.bestFit, 92)
    }

    /// An unscored role must sort last, not as zero — absence of a score isn't a bad score.
    func testUnscoredRolesSortLastRatherThanAsZero() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Stripe",
            others: [
                (role("unscored", "B", .new, fit: nil), "Stripe"),
                (role("scored", "A", .new, fit: 40), "Stripe")
            ]
        )
        XCTAssertEqual(result.openRoles.map(\.jobID), ["scored", "unscored"])
        XCTAssertEqual(result.bestFit, 40, "an unscored role must not define the best fit")
    }

    func testBestFitIsNilWhenNothingIsScored() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Stripe",
            others: [(role("b", "B", .new, fit: nil), "Stripe")]
        )
        XCTAssertNil(result.bestFit)
        XCTAssertEqual(result.openRoles.count, 1)
    }

    // MARK: - Rejections

    /// Informational, and surfaced regardless of the viewed job's status.
    func testRejectionsAreReportedSeparatelyFromOpenRoles() {
        let result = build(
            viewed: role("a", "TPM", .applied), company: "Stripe",
            others: [
                (role("rej", "Old TPM", .rejected), "Stripe"),
                (role("open", "New TPM", .new, fit: 88), "Stripe")
            ]
        )
        XCTAssertEqual(result.rejectedRoles.map(\.jobID), ["rej"])
        XCTAssertEqual(result.openRoles.map(\.jobID), ["open"])
    }

    func testRejectionAloneStillProducesContext() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Stripe",
            others: [(role("rej", "Old TPM", .rejected), "Stripe")]
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.openRoles.isEmpty)
    }

    /// The common case: nothing to say, so the line must not render.
    func testSingleRoleCompanyProducesNothing() {
        let result = build(
            viewed: role("a", "TPM", .pursuing), company: "Stripe",
            others: [(role("b", "Other", .new, fit: 90), "Datadog")]
        )
        XCTAssertTrue(result.isEmpty)
    }
}
