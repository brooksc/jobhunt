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

    func testPageCountComesFromTheReportedTotal() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(total: 17, firstPageCount: 17, maxPages: 50), 1)
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(total: 41, firstPageCount: 20, maxPages: 50), 3)
    }

    /// The cap applies to the tenant's own `total`, not just to unbounded probing: Workday's
    /// backend sometimes reports a `total` far above what it will actually serve, and requests past
    /// that offset return page 0 again.
    func testTheCapBoundsEvenAReportedTotal() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(total: 23609, firstPageCount: 20, maxPages: 50), 50)
    }

    /// With no `total`, a short first page already means there is nothing more — probing further
    /// would be a wasted request on every small board.
    func testWithoutATotalOnlyAFullFirstPageJustifiesMorePages() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(total: nil, firstPageCount: 7, maxPages: 50), 1)
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(total: nil, firstPageCount: 20, maxPages: 50), 50)
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

    /// A tenant reporting `total: 1` while serving a full page was declared complete after one page.
    /// `total` is advisory; a full page always justifies looking at the next one.
    func testAnUnderreportedTotalDoesNotEndPagination() {
        XCTAssertGreaterThan(
            WorkdayJobBoard.pagesToFetch(total: 1, firstPageCount: 20, maxPages: 5), 1,
            "a full first page means there may be more, whatever the tenant claims"
        )
    }

    /// A short first page is still the end of the board.
    func testAShortFirstPageStillEndsPagination() {
        XCTAssertEqual(WorkdayJobBoard.pagesToFetch(total: 999, firstPageCount: 7, maxPages: 5), 1)
    }

    func testTheCapStillBounds() {
        XCTAssertEqual(
            WorkdayJobBoard.pagesToFetch(total: 99999, firstPageCount: 20, maxPages: 5), 5
        )
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
}
