import Foundation
import XCTest
@testable import JobhuntCore

/// A sweep that couldn't reach a page used to report exactly like one that verified it was live —
/// the unverifiable result was dropped on the floor. Job #164 (Cloudflare 403) and the LinkedIn
/// rotation cap both hit this: the user reads "all still available" and assumes detection is broken.
final class AvailabilitySweepTests: XCTestCase {
    private func unverified(_ reason: UnverifiedReason, id: String = UUID().uuidString) -> UnverifiedJobResult {
        UnverifiedJobResult(
            jobID: id, jobNumber: 1, company: "Acme", title: "TPM",
            url: URL(string: "https://example.com/j"), reason: reason, detail: "detail"
        )
    }

    func testFullyVerifiedSweepHasNoNotice() {
        XCTAssertNil(AvailabilitySweep(gone: []).unverifiedSummary)
    }

    func testSummaryCountsAndNamesTheReason() {
        let sweep = AvailabilitySweep(gone: [], unverified: [unverified(.botChallenge)])
        let summary = try? XCTUnwrap(sweep.unverifiedSummary)
        XCTAssertEqual(summary, "Unable to check 1 job — 1 blocked by bot protection.")
    }

    func testSummaryPluralisesAndGroupsReasons() {
        let sweep = AvailabilitySweep(gone: [], unverified: [
            unverified(.botChallenge), unverified(.botChallenge), unverified(.rateLimited)
        ])
        let summary = sweep.unverifiedSummary ?? ""
        XCTAssertTrue(summary.hasPrefix("Unable to check 3 jobs — "), summary)
        XCTAssertTrue(summary.contains("2 blocked by bot protection"), summary)
        XCTAssertTrue(summary.contains("1 LinkedIn rate-limited the check"), summary)
    }

    /// Most-common reason first, so the headline names the dominant cause.
    func testReasonsAreOrderedByCount() {
        let sweep = AvailabilitySweep(gone: [], unverified: [
            unverified(.rateLimited), unverified(.botChallenge), unverified(.botChallenge)
        ])
        XCTAssertEqual(sweep.unverifiedByReason.first?.reason, .botChallenge)
        XCTAssertEqual(sweep.unverifiedByReason.first?.count, 2)
    }

    /// Ordering must not depend on dictionary iteration order, or the sentence would vary run to run.
    func testSummaryIsStableAcrossRuns() {
        let items = [unverified(.botChallenge), unverified(.rateLimited), unverified(.noURL)]
        let first = AvailabilitySweep(gone: [], unverified: items).unverifiedSummary
        for _ in 0 ..< 20 {
            XCTAssertEqual(AvailabilitySweep(gone: [], unverified: items).unverifiedSummary, first)
        }
    }

    func testEveryReasonHasUserFacingCopy() {
        for reason in UnverifiedReason.allCases {
            XCTAssertFalse(reason.summary.isEmpty, reason.rawValue)
            XCTAssertFalse(reason.summary.contains("_"), "\(reason.rawValue) leaks a raw identifier")
        }
    }

    /// Gone results and unverified ones are independent: finding one expired job says nothing about
    /// the ones that couldn't be reached.
    func testGoneAndUnverifiedCoexist() throws {
        let gone = try GoneJobResult(
            jobID: "g", jobNumber: 2, company: "Acme", title: "PM",
            url: XCTUnwrap(URL(string: "https://example.com/g")), reason: "HTTP 404"
        )
        let sweep = AvailabilitySweep(gone: [gone], unverified: [unverified(.botChallenge)])
        XCTAssertEqual(sweep.gone.count, 1)
        XCTAssertNotNil(sweep.unverifiedSummary)
    }
}
