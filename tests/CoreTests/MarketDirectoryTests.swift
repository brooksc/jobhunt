import Foundation
import XCTest
@testable import JobhuntCore

/// The public directory of ATS boards (TASK-696).
///
/// The dataset is third-party input tracking a branch, so most of what's defended here is that a
/// tampered or malformed entry can at worst name a board that doesn't exist — never a host jobhunt
/// didn't mean to contact.
final class MarketDirectoryTests: XCTestCase {
    // MARK: - Slug entries

    func testAPlainSlugBecomesABoard() throws {
        let board = try XCTUnwrap(MarketDirectory.board(kind: "greenhouse", entry: "databricks"))
        XCTAssertEqual(board.kind, "greenhouse")
        XCTAssertEqual(board.slug, "databricks")
    }

    /// The dataset is fetched from a repository that tracks `main`. An entry that could change the
    /// host must never survive validation.
    func testAnEntryCanNeverChangeTheHost() {
        for hostile in [
            "evil.com/../..", "acme@evil.com", "acme/jobs", "acme?x=1",
            "acme#@evil.com", "../../etc/passwd", "acme:8080"
        ] {
            XCTAssertNil(
                MarketDirectory.board(kind: "greenhouse", entry: hostile),
                "“\(hostile)” must not become a board"
            )
        }
    }

    func testBlankAndEmptyEntriesAreDropped() {
        XCTAssertNil(MarketDirectory.board(kind: "greenhouse", entry: ""))
        XCTAssertNil(MarketDirectory.board(kind: "greenhouse", entry: "   "))
    }

    // MARK: - Workday triples

    func testAWorkdayTripleBecomesABoardURL() throws {
        let board = try XCTUnwrap(
            MarketDirectory.board(kind: "workday", entry: "2020companies|wd1|external_careers")
        )
        XCTAssertEqual(board.kind, "workday")
        XCTAssertEqual(
            board.slug, "https://2020companies.wd1.myworkdayjobs.com/external_careers",
            "Workday keeps its whole config in the URL, so the slug IS the URL"
        )
    }

    /// The tenant and instance become DNS labels, so a dot in either can only build a host that
    /// cannot resolve. Harmless — the vendor suffix is always appended, so nothing escapes
    /// myworkdayjobs.com — but a wasted lookup on every sweep, so it's refused at parse time.
    func testADottedTenantOrInstanceIsRejectedAsAnImpossibleHost() {
        XCTAssertNil(MarketDirectory.board(kind: "workday", entry: "evil.com|wd1|careers"))
        XCTAssertNil(MarketDirectory.board(kind: "workday", entry: "acme|wd1.evil.com|careers"))
        XCTAssertNotNil(
            MarketDirectory.board(kind: "workday", entry: "acme|wd1|careers.v2"),
            "the site is a path segment, where a dot is ordinary"
        )
    }

    /// All three parts are interpolated — two into the host — so all three are guarded.
    func testAWorkdayTripleWithAnUnsafePartIsRejected() {
        for bad in [
            "tenant|wd1|../../etc", "tenant|wd1@evil.com|careers",
            "tenant|wd1", "tenant||careers", "|wd1|careers"
        ] {
            XCTAssertNil(
                MarketDirectory.board(kind: "workday", entry: bad),
                "“\(bad)” must not become a board"
            )
        }
    }

    /// The finished URL is re-parsed and its host confirmed, so the guard survives a future edit to
    /// the URL construction made without reading the comment.
    func testAWorkdayBoardAlwaysEndsOnMyworkdayjobs() throws {
        let board = try XCTUnwrap(
            MarketDirectory.board(kind: "workday", entry: "acme|wd5|careers")
        )
        let host = try XCTUnwrap(URL(string: board.slug)?.host)
        XCTAssertTrue(host.hasSuffix(".myworkdayjobs.com"), host)
    }

    // MARK: - Decoding

    func testAFileOfSlugsDecodes() {
        let data = Data(#"["databricks","stripe","","not/valid","coinbase"]"#.utf8)
        let boards = MarketDirectory.decode(data, kind: "greenhouse")
        XCTAssertEqual(boards.map(\.slug), ["databricks", "stripe", "coinbase"])
    }

    /// A bad row is dropped silently on purpose: the dataset carries thousands of entries, a few of
    /// them malformed at any moment, and a log line each would bury the run.
    func testGarbageDecodesToNothingRatherThanThrowing() {
        XCTAssertTrue(MarketDirectory.decode(Data("not json".utf8), kind: "greenhouse").isEmpty)
        XCTAssertTrue(MarketDirectory.decode(Data(#"{"jobs":[]}"#.utf8), kind: "greenhouse").isEmpty)
        XCTAssertTrue(MarketDirectory.decode(Data(#"[1,2,3]"#.utf8), kind: "greenhouse").isEmpty)
    }

    /// iCIMS is in the dataset and deliberately not listed here — jobhunt has no iCIMS provider, and
    /// sweeping boards it cannot read would only manufacture failures. (All 22 postings career-ops
    /// had to give up on were iCIMS.)
    func testOnlyVendorsJobhuntCanReadAreListed() {
        XCTAssertEqual(MarketDirectory.files.map(\.kind), ["greenhouse", "lever", "ashby", "workday"])
        XCTAssertFalse(MarketDirectory.files.contains { $0.kind == "icims" })
    }
}
