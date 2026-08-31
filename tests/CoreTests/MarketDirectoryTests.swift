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

/// The cache must never be replaced by something that decodes to nothing (TASK-701).
///
/// A 200 is not proof of a usable file. A malformed upstream commit or a truncated response would
/// otherwise overwrite the last known good copy, silently removing an entire vendor from every
/// sweep — and counting as fresh for a week, so it wouldn't even retry.
final class MarketDirectoryCacheTests: XCTestCase {
    private func stub(status: Int, body: String) -> URLSession {
        MockURLProtocol.reset()
        MockURLProtocol.handlers.append(("raw.githubusercontent.com", { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data(body.utf8))
        }))
        return MockURLProtocol.makeSession()
    }

    /// A directory of its own, per test. `load` WRITES what it fetched, so without this the
    /// stubbed two-entry response below lands in the real user's cache at
    /// ~/Library/Application Support/Jobhunt/market-directory — which is how running this suite
    /// replaced a working 8,333-entry Greenhouse directory with two boards, and left every sweep
    /// covering two Greenhouse companies until someone noticed.
    private var cacheRoot: URL!

    override func setUp() {
        super.setUp()
        cacheRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "jh-directory-\(UUID().uuidString)")
    }

    override func tearDown() {
        if let cacheRoot {
            try? FileManager.default.removeItem(at: cacheRoot)
        }
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testAGoodResponseIsAccepted() async throws {
        let session = stub(status: 200, body: #"["databricks","stripe"]"#)
        let loaded = await MarketDirectory.load(
            file: "greenhouse_companies.json", kind: "greenhouse",
            session: session, now: Date(), forceRefresh: true, cacheRoot: cacheRoot
        )
        XCTAssertNotNil(loaded)
        XCTAssertFalse(loaded?.degraded ?? true)
        XCTAssertEqual(try MarketDirectory.decode(XCTUnwrap(loaded?.data), kind: "greenhouse").count, 2)
    }

    /// The case that would have removed a vendor for a week: HTTP 200, non-empty body, zero boards.
    func testAResponseThatDecodesToNothingIsRefused() async {
        for body in ["not json at all", "[]", #"{"jobs":[]}"#, #"["not/valid","also bad"]"#] {
            let session = stub(status: 200, body: body)
            let loaded = await MarketDirectory.load(
                file: "greenhouse_companies.json", kind: "greenhouse",
                session: session, now: Date(), forceRefresh: true, cacheRoot: cacheRoot
            )
            // Either nothing (no cache to fall back on) or the cached copy flagged degraded —
            // never the new payload treated as good.
            if let loaded {
                XCTAssertTrue(loaded.degraded, "body: \(body)")
                XCTAssertFalse(
                    MarketDirectory.decode(loaded.data, kind: "greenhouse").isEmpty,
                    "a degraded fallback still has to be usable — body: \(body)"
                )
            }
        }
    }

    /// A vendor served from a stale or missing cache is reported, because a vendor quietly dropping
    /// out of every sweep is indistinguishable from that vendor having no matching jobs.
    func testADegradedVendorIsReportedRatherThanHidden() async {
        let session = stub(status: 500, body: "")
        let result = await MarketDirectory.boards(
            session: session, forceRefresh: true, cacheRoot: cacheRoot
        )
        XCTAssertFalse(
            result.degraded.isEmpty,
            "a vendor that couldn't be refreshed must be named, not silently dropped"
        )
    }
}

/// The cache must never be the user's real one during a test (TASK-704).
final class MarketDirectoryIsolationTests: XCTestCase {
    /// The specific accident this guards: `load` writes what it fetched, so a stubbed response in a
    /// test that forgot to pass `cacheRoot` overwrites the production directory — and the write
    /// counts as fresh for a week, so the loss is silent and lasts.
    func testAnOverriddenRootIsUsedInsteadOfApplicationSupport() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "jh-isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let overridden = try XCTUnwrap(
            MarketDirectory.cacheURL(file: "greenhouse_companies.json", root: root)
        )
        let production = try XCTUnwrap(
            MarketDirectory.cacheURL(file: "greenhouse_companies.json")
        )
        XCTAssertTrue(overridden.path.hasPrefix(root.path))
        XCTAssertNotEqual(overridden, production)
        XCTAssertFalse(
            overridden.path.contains("Application Support/Jobhunt/market-directory"),
            "a test's writes must not be able to reach the real cache"
        )
    }

    /// And a write through the override really does land there, not beside the store.
    func testAWriteThroughTheOverrideStaysInTheOverride() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "jh-isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.handlers.append(("raw.githubusercontent.com", { request in
            (
                HTTPURLResponse(
                    url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!,
                Data(#"["acme-isolation-probe"]"#.utf8)
            )
        }))

        _ = await MarketDirectory.load(
            file: "greenhouse_companies.json", kind: "greenhouse",
            session: MockURLProtocol.makeSession(), now: Date(), forceRefresh: true,
            cacheRoot: root
        )
        let written = root.appending(path: "greenhouse_companies.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: written.path),
            "the fetched file should be cached under the override"
        )
    }
}
