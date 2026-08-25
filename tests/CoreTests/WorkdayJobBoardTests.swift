import Foundation
import XCTest
@testable import JobhuntCore

/// Reading a Workday tenant's public CXS API (TASK-690, auto-search M1).
///
/// Network-free: the network paths are thin loops over these decoders and this arithmetic, and
/// what's worth pinning is the payload shape and the pagination/date rules — each of which exists
/// because a live tenant behaved in a way the obvious implementation gets wrong.
final class WorkdayJobBoardTests: XCTestCase {
    private func board(host: String = "23andme.wd5.myworkdayjobs.com") -> WorkdayJobBoard.Board {
        WorkdayJobBoard.Board(tenant: "23andme", site: "23", host: host)
    }

    private func listPayload(_ postings: String, total: Int? = nil) -> Data {
        let totalField = total.map { "\"total\": \($0)," } ?? ""
        return Data("{ \(totalField) \"jobPostings\": [\(postings)] }".utf8)
    }

    // MARK: - Board identity

    func testDerivesTheBoardFromAPostingDeepLink() throws {
        let url = try XCTUnwrap(URL(
            string: "https://23andme.wd5.myworkdayjobs.com/23/job/Palo-Alto-HQ/Senior-Product-Designer_2026048"
        ))
        let board = try XCTUnwrap(WorkdayJobBoard.board(for: url))
        XCTAssertEqual(board.tenant, "23andme")
        XCTAssertEqual(board.site, "23")
        XCTAssertEqual(
            board.listEndpoint?.absoluteString,
            "https://23andme.wd5.myworkdayjobs.com/wday/cxs/23andme/23/jobs"
        )
    }

    /// A user adding a search source pastes the board's landing page, which has no posting segment
    /// at all. `AvailabilityChecker.workdayCXSQuery` can't parse this — it needs a requisition id —
    /// which is why this parser exists alongside it rather than reusing it.
    func testDerivesTheBoardFromABareBoardURL() throws {
        let url = try XCTUnwrap(URL(string: "https://acme.wd1.myworkdayjobs.com/en-US/acme-careers"))
        let board = try XCTUnwrap(WorkdayJobBoard.board(for: url))
        XCTAssertEqual(board.tenant, "acme")
        XCTAssertEqual(board.site, "acme-careers", "the locale segment must not be read as the site")
    }

    func testANonWorkdayURLHasNoBoard() throws {
        let url = try XCTUnwrap(URL(string: "https://boards.greenhouse.io/acme/jobs/4567"))
        XCTAssertNil(WorkdayJobBoard.board(for: url))
    }

    // MARK: - List decoding

    func testDecodesTheFieldsTheListPublishes() {
        let roles = WorkdayJobBoard.decodeRoles(listPayload("""
        {
          "title": "Senior Product Designer",
          "externalPath": "/job/Palo-Alto-HQ/Senior-Product-Designer_2026048",
          "locationsText": "Palo Alto (HQ)",
          "postedOn": "Posted 19 Days Ago",
          "bulletFields": ["2026048"]
        }
        """), board: board())

        XCTAssertEqual(roles.count, 1)
        XCTAssertEqual(roles.first?.id, "2026048")
        XCTAssertEqual(roles.first?.title, "Senior Product Designer")
        XCTAssertEqual(roles.first?.locationName, "Palo Alto (HQ)")
        XCTAssertEqual(
            roles.first?.absoluteURL,
            "https://23andme.wd5.myworkdayjobs.com/23/job/Palo-Alto-HQ/Senior-Product-Designer_2026048",
            "the path is relative to the SITE — without that segment the URL 404s"
        )
        XCTAssertNil(roles.first?.updatedAt, "Workday publishes no update timestamp at all")
    }

    func testARowWithNoTitleOrNoPathIsSkipped() {
        let roles = WorkdayJobBoard.decodeRoles(listPayload("""
        { "title": "", "externalPath": "/job/HQ/Blank_1" },
        { "title": "No Path", "externalPath": "" },
        { "title": "Keeper", "externalPath": "/job/HQ/Keeper_2" }
        """), board: board())
        XCTAssertEqual(roles.map(\.title), ["Keeper"])
    }

    func testGarbageIsNotABoard() {
        XCTAssertTrue(WorkdayJobBoard.decodeRoles(Data("not json".utf8), board: board()).isEmpty)
        XCTAssertEqual(WorkdayJobBoard.decodePageCount(Data("not json".utf8)), 0)
    }

    // MARK: - Location

    /// Some tenants report `"5 Locations"` — a count, not a place. No location filter can ever
    /// match that, so the primary location is recovered from the URL path instead.
    func testARolledUpLocationFallsBackToTheURLPath() {
        let roles = WorkdayJobBoard.decodeRoles(listPayload("""
        {
          "title": "Network Engineer",
          "externalPath": "/job/Hyderabad-Telangana-India/Network-Engineer_R-65193-1",
          "locationsText": "5 Locations"
        }
        """), board: board())
        XCTAssertEqual(roles.first?.locationName, "Hyderabad Telangana India")
    }

    func testAMissingLocationFallsBackToTheURLPath() {
        let roles = WorkdayJobBoard.decodeRoles(listPayload("""
        { "title": "Engineer", "externalPath": "/job/Palo-Alto-HQ/Engineer_1" }
        """), board: board())
        XCTAssertEqual(roles.first?.locationName, "Palo Alto HQ")
    }

    /// A real location that merely starts with a digit ("1 Infinite Loop") is not a rollup.
    func testARealLocationIsNotMistakenForARollup() {
        XCTAssertTrue(WorkdayJobBoard.isLocationRollup("5 Locations"))
        XCTAssertTrue(WorkdayJobBoard.isLocationRollup("2 locations"))
        XCTAssertFalse(WorkdayJobBoard.isLocationRollup("1 Infinite Loop"))
        XCTAssertFalse(WorkdayJobBoard.isLocationRollup("Palo Alto (HQ)"))
    }

    func testTheLocationHintReadsOnlyTheSegmentAfterJob() {
        XCTAssertEqual(WorkdayJobBoard.locationFromPath("/job/Berlin-Germany/Engineer_1"), "Berlin Germany")
        XCTAssertNil(
            WorkdayJobBoard.locationFromPath("/details/Berlin/Engineer_1"),
            "only /job/ carries the location by convention — guessing from any segment would match company slugs"
        )
    }

    // MARK: - Dates

    func testRelativePostedLabelsBecomeDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(WorkdayJobBoard.parsePostedOn("Posted Today", now: now), now)
        XCTAssertEqual(
            WorkdayJobBoard.parsePostedOn("Posted Yesterday", now: now),
            now.addingTimeInterval(-86400)
        )
        XCTAssertEqual(
            WorkdayJobBoard.parsePostedOn("Posted 5 Days Ago", now: now),
            now.addingTimeInterval(-5 * 86400)
        )
    }

    /// The one that matters. `"30+ Days Ago"` is an unbounded bucket: the posting could be a year
    /// old. Reading it as 30 days invents a first-published date, and every freshness decision
    /// downstream inherits the fiction.
    func testTheUnboundedBucketYieldsNoDate() {
        XCTAssertNil(WorkdayJobBoard.parsePostedOn("Posted 30+ Days Ago"))
        XCTAssertNil(WorkdayJobBoard.parsePostedOn(nil))
        XCTAssertNil(WorkdayJobBoard.parsePostedOn("Posted recently"))
    }

    func testTheDetailStartDateParses() throws {
        let date = try XCTUnwrap(WorkdayJobBoard.parseStartDate("2026-08-03"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(calendar.component(.year, from: date), 2026)
        XCTAssertEqual(calendar.component(.month, from: date), 8)
        XCTAssertEqual(calendar.component(.day, from: date), 3)
        XCTAssertNil(WorkdayJobBoard.parseStartDate("last Tuesday"))
    }

    // MARK: - Early stop

    private func role(daysAgo: Double?, now: Date) -> GreenhouseJobBoard.OpenRole {
        GreenhouseJobBoard.OpenRole(
            id: "\(daysAgo ?? -1)", title: "Role", locationName: nil,
            absoluteURL: "https://example.com", updatedAt: nil,
            firstPublished: daysAgo.map { now.addingTimeInterval(-$0 * 86400) }
        )
    }

    func testPaginationStopsOnceAPageIsEntirelyPastTheWindow() {
        let now = Date()
        let since = now.addingTimeInterval(-7 * 86400)
        XCTAssertTrue(WorkdayJobBoard.pageIsPastWindow(
            [role(daysAgo: 20, now: now), role(daysAgo: 25, now: now)], since: since
        ))
    }

    /// The sort isn't perfectly monotonic — real tenants return day labels with about a day of
    /// jitter — so a page straddling the cutoff must not stop the loop.
    func testAPageStraddlingTheCutoffDoesNotStopPagination() {
        let now = Date()
        let since = now.addingTimeInterval(-7 * 86400)
        XCTAssertFalse(WorkdayJobBoard.pageIsPastWindow(
            [role(daysAgo: 2, now: now), role(daysAgo: 8, now: now)], since: since
        ))
    }

    /// Undated postings are invisible to the early stop. A tenant whose postings are all in the
    /// `30+` bucket would otherwise be truncated at page 1 — silently, since the stop looks
    /// exactly like a completed listing.
    func testAPageOfUndatedPostingsNeverStopsPagination() {
        let now = Date()
        XCTAssertFalse(WorkdayJobBoard.pageIsPastWindow(
            [role(daysAgo: nil, now: now), role(daysAgo: nil, now: now)],
            since: now.addingTimeInterval(-7 * 86400)
        ))
        XCTAssertFalse(WorkdayJobBoard.pageIsPastWindow([], since: now.addingTimeInterval(-86400)))
    }

    func testNoWindowNeverStopsEarly() {
        let now = Date()
        XCTAssertFalse(WorkdayJobBoard.pageIsPastWindow([role(daysAgo: 900, now: now)], since: nil))
    }

    // MARK: - Pagination arithmetic

    /// A short first page is the end of the board — probing further would waste a request on every
    /// small board.
    func testOnlyAFullFirstPageJustifiesMorePages() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(firstPageCount: 17, maxPages: 50), 1)
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(firstPageCount: 0, maxPages: 50), 1)
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(firstPageCount: 20, maxPages: 50), 50)
    }

    /// The cap is what bounds pagination, since the tenant's own `total` is not trustworthy in
    /// either direction: Workday's backend both underreports it and sometimes reports far above
    /// what it will actually serve, with requests past that offset returning page 0 again.
    func testTheCapBounds() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(firstPageCount: 20, maxPages: 50), 50)
    }

    // MARK: - Retry classification

    /// A 4xx other than 429 is the server saying the request itself is wrong; retrying burns the
    /// budget. 429 and 5xx are the WAF rate-limiting in bursts, which is exactly what a retry is
    /// for — without it a single 429 silently truncates an entire tenant.
    func testOnlyTransientFailuresAreRetried() {
        XCTAssertTrue(WorkdayJobBoard.isRetryable(status: 429))
        XCTAssertTrue(WorkdayJobBoard.isRetryable(status: 503))
        XCTAssertTrue(WorkdayJobBoard.isRetryable(status: nil), "transport error — no status")
        XCTAssertFalse(WorkdayJobBoard.isRetryable(status: 404))
        XCTAssertFalse(WorkdayJobBoard.isRetryable(status: 400))
    }

    // MARK: - Detail decoding

    private func detailPayload(description: String = "<p>Design <b>things</b>.</p>") -> Data {
        Data("""
        {
          "jobPostingInfo": {
            "title": "Senior Product Designer",
            "jobDescription": "\(description)",
            "location": "Palo Alto (HQ)",
            "startDate": "2026-08-03",
            "jobReqId": "2026048",
            "externalUrl": "https://23andme.wd5.myworkdayjobs.com/23/job/Palo-Alto-HQ/Senior-Product-Designer_2026048"
          }
        }
        """.utf8)
    }

    func testTheDetailEndpointSuppliesTheBodyTheListLacks() throws {
        let posting = try XCTUnwrap(
            WorkdayJobBoard.decodePosting(detailPayload(), board: board(), urlString: nil)
        )
        XCTAssertEqual(posting.title, "Senior Product Designer")
        XCTAssertEqual(posting.locationName, "Palo Alto (HQ)")
        XCTAssertTrue(posting.contentPlain.contains("Design"))
        XCTAssertFalse(posting.contentPlain.contains("<b>"), "HTML is stripped for the extractor")
        XCTAssertEqual(posting.providerName, "Workday")
        XCTAssertNotNil(posting.firstPublished, "startDate is absolute — better than the list's relative label")
    }

    /// Same rule as Greenhouse: a posting with a title and no body gives a refresh nothing to do,
    /// and writing an empty description over a good capture is strictly worse than leaving it.
    func testAPostingWithNoBodyIsNotUsable() {
        XCTAssertNil(WorkdayJobBoard.decodePosting(detailPayload(description: ""), board: board(), urlString: nil))
        XCTAssertNil(WorkdayJobBoard.decodePosting(
            Data(#"{"jobPostingInfo":{}}"#.utf8),
            board: board(),
            urlString: nil
        ))
        XCTAssertNil(WorkdayJobBoard.decodePosting(Data("not json".utf8), board: board(), urlString: nil))
    }

    // MARK: - Provider wiring

    func testThePostingPathIsDerivedFromThePublicURL() throws {
        let url = try XCTUnwrap(URL(
            string: "https://23andme.wd5.myworkdayjobs.com/en-US/23/job/Palo-Alto-HQ/Designer_123"
        ))
        XCTAssertEqual(
            WorkdayProvider.externalPath(from: url, site: "23"),
            "/job/Palo-Alto-HQ/Designer_123",
            "the detail endpoint wants the path minus the locale and site segments"
        )
    }

    func testAURLThatIsNotWorkdayYieldsNoRoles() async {
        let roles = await WorkdayProvider().listOpenRoles(
            atsID: "wd:acme:R-1", company: "Acme",
            urlString: "https://boards.greenhouse.io/acme/jobs/1", session: .shared
        )
        XCTAssertTrue(roles.isEmpty, "no network call should be attempted for a non-Workday URL")
    }
}

/// Coverage losses in the Workday client, at market scale (TASK-703).
final class WorkdayCoverageTests: XCTestCase {
    private func role(daysAgo: Double?, now: Date) -> GreenhouseJobBoard.OpenRole {
        GreenhouseJobBoard.OpenRole(
            id: "\(daysAgo ?? -1)", title: "Role", locationName: nil,
            absoluteURL: "https://example.com", updatedAt: nil,
            firstPublished: daysAgo.map { now.addingTimeInterval(-$0 * 86400) }
        )
    }

    /// The stop keyed on the OLDEST row, so a single stale outlier among fresh postings ended the
    /// scan — losing everything after it on a large tenant.
    func testOneOldOutlierDoesNotStopPagination() {
        let now = Date()
        let since = now.addingTimeInterval(-7 * 86400)
        XCTAssertFalse(
            WorkdayJobBoard.pageIsPastWindow(
                [role(daysAgo: 1, now: now), role(daysAgo: 2, now: now), role(daysAgo: 400, now: now)],
                since: since
            ),
            "the page is mostly fresh — one old row says nothing about what follows"
        )
    }

    /// A page mixing dated and undated rows says nothing about what comes next, because the undated
    /// ones could be anything.
    func testAMixedPageDoesNotStopPagination() {
        let now = Date()
        XCTAssertFalse(WorkdayJobBoard.pageIsPastWindow(
            [role(daysAgo: 400, now: now), role(daysAgo: nil, now: now)],
            since: now.addingTimeInterval(-7 * 86400)
        ))
    }

    /// It still stops when the whole page really is past the window.
    func testAWhollyStalePageStillStops() {
        let now = Date()
        XCTAssertTrue(WorkdayJobBoard.pageIsPastWindow(
            [role(daysAgo: 300, now: now), role(daysAgo: 400, now: now)],
            since: now.addingTimeInterval(-7 * 86400)
        ))
    }

    /// A tenant reporting `total: 1` while serving a full page was declared complete after two
    /// pages, losing everything past the fortieth posting. Deriving a page budget from `total` is
    /// what did that, so nothing derives one now: a full first page paginates to the cap.
    func testAnUnderreportedTotalDoesNotBoundPagination() {
        XCTAssertEqual(
            WorkdayJobBoard.pagesToFetch(firstPageCount: 20, maxPages: 5), 5,
            "a full first page means there may be more, whatever the tenant claims"
        )
    }

    /// A short first page is still the end of the board.
    func testAShortFirstPageStillEndsPagination() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(firstPageCount: 7, maxPages: 5), 1)
    }

    func testTheCapStillBounds() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(firstPageCount: 20, maxPages: 5), 5)
    }

    /// The cap has to hold at its smallest value too: `max(2, …)` on the outside of the old
    /// expression returned 2 here, so `SourceResolver`'s deliberately-one-page probe asked a
    /// stranger's board for a second page.
    func testAOnePageCapFetchesOnePage() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(firstPageCount: 20, maxPages: 1), 1)
    }

    /// 408 is a timeout the server chose to report rather than drop — as transient as the dropped
    /// connection that arrives with no status at all.
    func testATimeoutStatusIsRetryable() {
        XCTAssertTrue(WorkdayJobBoard.isRetryable(status: 408))
        XCTAssertFalse(WorkdayJobBoard.isRetryable(status: 404))
    }

    /// A server that says how long to wait knows better than a fixed backoff — but a hostile value
    /// must not stall a sweep for a day.
    func testRetryAfterIsHonouredButClamped() {
        XCTAssertEqual(WorkdayJobBoard.retryAfter("5"), .seconds(5))
        XCTAssertEqual(WorkdayJobBoard.retryAfter("86400"), .seconds(30), "clamped")
        XCTAssertNil(WorkdayJobBoard.retryAfter(nil))
        XCTAssertNil(WorkdayJobBoard.retryAfter("not a duration"))
    }

    /// `Double("inf")` parses, and `Duration.seconds(_:)` traps on it — so a board answering a
    /// retryable status with `Retry-After: inf` crashed the app mid-sweep. Same for any overflowing
    /// exponent. Reaching a `fatalError` from a response header is a third party halting jobhunt.
    func testAnInfiniteRetryAfterDoesNotCrash() {
        // Not honoured at all rather than clamped: a header that isn't a duration tells us nothing
        // about when to retry, and nil means "use the normal backoff".
        XCTAssertNil(WorkdayJobBoard.retryAfter("inf"))
        XCTAssertNil(WorkdayJobBoard.retryAfter("Infinity"))
        XCTAssertNil(WorkdayJobBoard.retryAfter("1e400"), "overflows to infinity")
        // A merely enormous but finite value is a duration, so it clamps like any other.
        XCTAssertEqual(WorkdayJobBoard.retryAfter("1e308"), .seconds(30))
    }

    func testANonNumericOrNegativeRetryAfterIsIgnored() {
        XCTAssertNil(WorkdayJobBoard.retryAfter("nan"))
        XCTAssertNil(WorkdayJobBoard.retryAfter("-1"))
        XCTAssertNil(WorkdayJobBoard.retryAfter("-inf"))
    }
}

/// Why pagination stopped, and why the difference decides whether a board is ever read again
/// (TASK-703 follow-up).
///
/// The first version of the truncation fix threw on *any* incomplete listing. But a market pass
/// deliberately reads only the newest five pages of every tenant, so "incomplete" is the designed
/// outcome for every large employer — and throwing turned each of them into a permanently
/// unreachable board yielding nothing at all. Measured against live tenants at the time: Allstate
/// 441 open roles, Humana 362, NVIDIA 2,000, Zillow 110 — every one over the 100-role window.
final class WorkdayStopReasonTests: XCTestCase {
    private let board = WorkdayJobBoard.Board(
        tenant: "acme", site: "careers", host: "acme.wd5.myworkdayjobs.com"
    )

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    /// `count` postings, each with a distinct id so pages don't collapse when deduplicated.
    private func page(_ count: Int, total: Int?, offset: Int = 0) -> Data {
        let postings = (0 ..< count).map { index in
            """
            {"title":"Role \(offset + index)","externalPath":"/job/Seattle/Role_R\(offset + index)",\
            "postedOn":"Posted Today"}
            """
        }.joined(separator: ",")
        let totalField = total.map { "\"total\": \($0)," } ?? ""
        return Data("{ \(totalField) \"jobPostings\": [\(postings)] }".utf8)
    }

    private func stubEveryPageFull(total: Int) {
        MockURLProtocol.handlers.append(("wday/cxs", { [self] request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, page(WorkdayJobBoard.pageSize, total: total))
        }))
    }

    /// The regression that mattered: a tenant larger than the page cap is *bounded*, not failed, so
    /// the market pass keeps its newest 100 roles instead of discarding the tenant entirely.
    func testHittingThePageCapIsBoundedNotFailed() async {
        stubEveryPageFull(total: 2000)
        let listing = await WorkdayJobBoard.listOpenRoles(
            board: board, session: MockURLProtocol.makeSession(), maxPages: 5
        )
        XCTAssertEqual(listing.stop, .bounded)
        XCTAssertFalse(listing.didFail, "the cap is the caller's own bound, not the tenant failing")
        XCTAssertTrue(listing.isPartial)
        XCTAssertEqual(listing.roles.count, 5 * WorkdayJobBoard.pageSize)
    }

    /// And the source turns that into roles rather than an error — the actual user-visible effect.
    func testALargeTenantStillYieldsItsNewestRoles() async throws {
        stubEveryPageFull(total: 2000)
        let postings = try await WorkdaySource().fetchRecent(
            config: SourceConfig(
                slug: "https://acme.wd5.myworkdayjobs.com/careers",
                pageLimit: MarketSweeper.marketPageLimit
            ),
            since: nil,
            session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(
            postings.count, MarketSweeper.marketPageLimit * WorkdayJobBoard.pageSize,
            "a 2,000-role tenant must contribute its newest 100, not throw"
        )
    }

    /// The original bug still stays fixed: a mid-listing failure is not a complete board.
    func testATenantThatStopsAnsweringMidListingFails() async {
        var served = 0
        MockURLProtocol.handlers.append(("wday/cxs", { [self] request in
            served += 1
            let url = request.url ?? URL(fileURLWithPath: "/")
            if served == 1 {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    page(WorkdayJobBoard.pageSize, total: 3000)
                )
            }
            return (
                HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }))
        let listing = await WorkdayJobBoard.listOpenRoles(
            board: board, session: MockURLProtocol.makeSession(), maxPages: 5
        )
        XCTAssertTrue(listing.didFail, "page one alone is not a 3,000-role tenant's open roles")
        XCTAssertFalse(listing.roles.isEmpty, "the rows it did get are still returned")
    }

    func testAPartialListingStillThrowsFromTheSource() async {
        MockURLProtocol.handlers.append(("wday/cxs", { request in
            (
                HTTPURLResponse(
                    url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 500,
                    httpVersion: nil, headerFields: nil
                )!,
                Data()
            )
        }))
        do {
            _ = try await WorkdaySource().fetchRecent(
                config: SourceConfig(slug: "https://acme.wd5.myworkdayjobs.com/careers", pageLimit: 5),
                since: nil,
                session: MockURLProtocol.makeSession()
            )
            XCTFail("a tenant that never answered must not read as a board with no open roles")
        } catch {}
    }

    /// A board that is genuinely empty is complete, not broken. The old `hitCap` expression was
    /// true whenever `pages == maxPages`, which includes the one-page probe — so every empty
    /// Workday board told the user their correct URL "didn't answer".
    func testAnEmptyBoardIsCompleteNotFailed() async {
        MockURLProtocol.handlers.append(("wday/cxs", { [self] request in
            (
                HTTPURLResponse(
                    url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!,
                page(0, total: 0)
            )
        }))
        let listing = await WorkdayJobBoard.listOpenRoles(
            board: board, session: MockURLProtocol.makeSession(), maxPages: 1
        )
        XCTAssertEqual(listing.stop, .complete)
        XCTAssertFalse(listing.didFail)
        XCTAssertTrue(listing.roles.isEmpty)
    }

    /// A board smaller than one page is complete too.
    func testAShortFirstPageIsComplete() async {
        MockURLProtocol.handlers.append(("wday/cxs", { [self] request in
            (
                HTTPURLResponse(
                    url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!,
                page(3, total: 3)
            )
        }))
        let listing = await WorkdayJobBoard.listOpenRoles(
            board: board, session: MockURLProtocol.makeSession(), maxPages: 5
        )
        XCTAssertEqual(listing.stop, .complete)
        XCTAssertEqual(listing.roles.count, 3)
    }
}
