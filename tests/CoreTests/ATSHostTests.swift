import Foundation
import XCTest
@testable import JobhuntCore

/// Outbound-host validation (TASK-703).
///
/// Both obvious spellings were in use here and both are wrong: `hasSuffix("myworkdayjobs.com")`
/// accepts `evilmyworkdayjobs.com`, and `contains("greenhouse.io")` accepts
/// `greenhouse.io.evil.com`. These requests carry no credentials, so this isn't exfiltration — but
/// a hostile URL could steer jobhunt's outbound traffic and have the reply parsed as a vendor's.
final class ATSHostTests: XCTestCase {
    func testTheDomainItselfAndItsSubdomainsBelong() {
        XCTAssertTrue(ATSHost.belongs("myworkdayjobs.com", to: "myworkdayjobs.com"))
        XCTAssertTrue(ATSHost.belongs("acme.wd5.myworkdayjobs.com", to: "myworkdayjobs.com"))
        XCTAssertTrue(ATSHost.belongs("JOBS.LEVER.CO", to: "lever.co"))
    }

    /// The attack the old check allowed.
    func testALookalikeDomainDoesNotBelong() {
        XCTAssertFalse(ATSHost.belongs("evilmyworkdayjobs.com", to: "myworkdayjobs.com"))
        XCTAssertFalse(ATSHost.belongs("notlever.co", to: "lever.co"))
        XCTAssertFalse(ATSHost.belongs("xgreenhouse.io", to: "greenhouse.io"))
    }

    /// The attack the `contains` check allowed.
    func testTheDomainAppearingEarlierInTheHostDoesNotBelong() {
        XCTAssertFalse(ATSHost.belongs("greenhouse.io.evil.com", to: "greenhouse.io"))
        XCTAssertFalse(ATSHost.belongs("myworkdayjobs.com.attacker.net", to: "myworkdayjobs.com"))
    }

    func testNonsenseDoesNotBelong() {
        XCTAssertFalse(ATSHost.belongs(nil, to: "lever.co"))
        XCTAssertFalse(ATSHost.belongs("", to: "lever.co"))
        XCTAssertFalse(ATSHost.belongs(".lever.co", to: "lever.co"))
    }

    /// The callers that matter: a lookalike host must not resolve to a board jobhunt would fetch.
    func testALookalikeHostYieldsNoWorkdayBoard() throws {
        let hostile = try XCTUnwrap(URL(string: "https://acme.evilmyworkdayjobs.com/careers"))
        XCTAssertNil(WorkdayJobBoard.board(for: hostile))
        XCTAssertNil(SourceResolver.identify(boardURL: hostile.absoluteString))

        let good = try XCTUnwrap(URL(string: "https://acme.wd5.myworkdayjobs.com/careers"))
        XCTAssertNotNil(WorkdayJobBoard.board(for: good))
    }

    /// And must not produce a dedup key, which is what discovery keys everything on.
    func testALookalikeHostYieldsNoATSIdentity() {
        XCTAssertNil(DuplicateDetector.atsPostingID(
            urlString: "https://greenhouse.io.evil.com/acme/jobs/4567"
        ))
        XCTAssertNil(DuplicateDetector.atsPostingID(
            urlString: "https://notlever.co/acme/abc-123"
        ))
        XCTAssertEqual(
            DuplicateDetector.atsPostingID(urlString: "https://boards.greenhouse.io/acme/jobs/4567"),
            "gh:4567", "the real host still works"
        )
    }
}
