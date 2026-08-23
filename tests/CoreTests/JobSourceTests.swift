import Foundation
import XCTest
@testable import JobhuntCore

/// Sweeping a board without starting from a posting (TASK-691, M2).
///
/// The behaviour worth pinning isn't the HTTP — it's the two rules that keep a sweep honest: an
/// empty board must be reported as *success with no rows* rather than as a failure, and no
/// implementation may issue a request per posting.
final class JobSourceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func stub(_ pattern: String, status: Int = 200, body: String) {
        MockURLProtocol.handlers.append((pattern, { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data(body.utf8))
        }))
    }

    // MARK: - Greenhouse

    func testGreenhouseSweepsABoardBySlug() async throws {
        stub("boards-api.greenhouse.io", body: """
        { "jobs": [
          { "id": 4567, "title": "Program Manager",
            "absolute_url": "https://boards.greenhouse.io/acme/jobs/4567",
            "location": { "name": "Remote, United States" },
            "first_published": "2026-08-01T09:00:00Z" }
        ] }
        """)
        let postings = try await GreenhouseSource().fetchRecent(
            config: SourceConfig(slug: "acme", company: "Acme"), since: nil,
            session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(postings.count, 1)
        XCTAssertEqual(postings.first?.title, "Program Manager")
        XCTAssertEqual(postings.first?.company, "Acme", "Greenhouse's list payload names no employer")
        XCTAssertEqual(postings.first?.locationRaw, "Remote, United States")
        XCTAssertEqual(postings.first?.dedupKey, "gh:4567")
        XCTAssertNil(
            postings.first?.descriptionPlain,
            "Greenhouse's list endpoint publishes no body, and fetching one per row is what the "
                + "pre-gate no-network rule forbids"
        )
    }

    /// The rule the whole `SourceError` type exists for. A board that migrated ATS answers 200 with
    /// an empty list, forever — reporting that as a failure would be wrong, and reporting a failure
    /// as an empty board is how a source goes quiet for weeks with nothing on screen saying so.
    func testAnEmptyBoardIsSuccessNotFailure() async throws {
        stub("boards-api.greenhouse.io", body: #"{ "jobs": [] }"#)
        let postings = try await GreenhouseSource().fetchRecent(
            config: SourceConfig(slug: "acme"), since: nil, session: MockURLProtocol.makeSession()
        )
        XCTAssertTrue(postings.isEmpty)
    }

    func testAnUnreachableBoardThrows() async {
        stub("boards-api.greenhouse.io", status: 404, body: "")
        do {
            _ = try await GreenhouseSource().fetchRecent(
                config: SourceConfig(slug: "gone"), since: nil, session: MockURLProtocol.makeSession()
            )
            XCTFail("a 404 board must not read as an empty board")
        } catch {
            guard case SourceError.unreachable = error else {
                return XCTFail("expected .unreachable, got \(error)")
            }
        }
    }

    func testAnEmptySlugIsMisconfiguredRatherThanFetched() async {
        do {
            _ = try await GreenhouseSource().fetchRecent(
                config: SourceConfig(slug: ""), since: nil, session: MockURLProtocol.makeSession()
            )
            XCTFail("an empty slug must not produce a request")
        } catch {
            guard case SourceError.misconfigured = error else {
                return XCTFail("expected .misconfigured, got \(error)")
            }
        }
    }

    // MARK: - Lever

    /// Lever ships the body in the board payload, so gate A gets it for free — no extra request,
    /// which is the only reason it's allowed to be here at all.
    func testLeverCarriesTheDescriptionFromTheBoardPayload() async throws {
        stub("api.lever.co", body: """
        [
          { "id": "abc-123", "text": "Senior Program Manager",
            "hostedUrl": "https://jobs.lever.co/acme/abc-123",
            "categories": { "location": "Remote, US" },
            "createdAt": 1786000000000,
            "descriptionPlain": "We are hiring.",
            "additionalPlain": "You will need 5 years of experience." }
        ]
        """)
        let postings = try await LeverSource().fetchRecent(
            config: SourceConfig(slug: "acme", company: "Acme"), since: nil,
            session: MockURLProtocol.makeSession()
        )
        let body = try XCTUnwrap(postings.first?.descriptionPlain)
        XCTAssertTrue(body.contains("We are hiring."))
        XCTAssertTrue(
            body.contains("5 years"),
            "the intro alone is marketing copy — the requirements live in additionalPlain"
        )
        XCTAssertNotNil(postings.first?.firstPublished, "createdAt is epoch milliseconds")
    }

    // MARK: - Ashby

    func testAshbySkipsPostingsTheEmployerHidFromTheirOwnBoard() async throws {
        stub("api.ashbyhq.com", body: """
        { "jobs": [
          { "id": "1", "title": "Listed Role", "jobUrl": "https://jobs.ashbyhq.com/acme/1",
            "location": "Remote", "isListed": true, "descriptionPlain": "Body." },
          { "id": "2", "title": "Hidden Role", "jobUrl": "https://jobs.ashbyhq.com/acme/2",
            "location": "Remote", "isListed": false, "descriptionPlain": "Body." }
        ] }
        """)
        let postings = try await AshbySource().fetchRecent(
            config: SourceConfig(slug: "acme"), since: nil, session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(postings.map(\.title), ["Listed Role"])
    }

    func testAshbyMalformedPayloadIsNotAnEmptyBoard() async {
        stub("api.ashbyhq.com", body: #"{"unexpected": true}"#)
        do {
            _ = try await AshbySource().fetchRecent(
                config: SourceConfig(slug: "acme"), since: nil, session: MockURLProtocol.makeSession()
            )
            XCTFail("a payload we can't read must not read as an empty board")
        } catch {
            guard case SourceError.malformedResponse = error else {
                return XCTFail("expected .malformedResponse, got \(error)")
            }
        }
    }

    // MARK: - Workday

    /// Workday is configured with a board URL rather than a slug, because the
    /// tenant/instance/site triple can't be derived from a company name — there's no rule that
    /// turns "Acme" into `acme.wd5`.
    func testWorkdayNeedsABoardURLNotASlug() async {
        do {
            _ = try await WorkdaySource().fetchRecent(
                config: SourceConfig(slug: "acme"), since: nil, session: MockURLProtocol.makeSession()
            )
            XCTFail("a bare slug can't identify a Workday tenant")
        } catch {
            guard case SourceError.misconfigured = error else {
                return XCTFail("expected .misconfigured, got \(error)")
            }
        }
    }

    func testWorkdaySweepsATenantFromItsBoardURL() async throws {
        stub("wday/cxs", body: """
        { "total": 1, "jobPostings": [
          { "title": "Program Manager",
            "externalPath": "/job/Palo-Alto-HQ/Program-Manager_R-65193-1",
            "locationsText": "Palo Alto (HQ)", "postedOn": "Posted 3 Days Ago",
            "bulletFields": ["R-65193"] }
        ] }
        """)
        let postings = try await WorkdaySource().fetchRecent(
            config: SourceConfig(slug: "https://acme.wd5.myworkdayjobs.com/careers"),
            since: nil, session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(postings.count, 1)
        XCTAssertEqual(postings.first?.company, "acme", "the tenant names the employer when nothing else does")
        XCTAssertEqual(
            postings.first?.dedupKey, "wd:acme:R-65193",
            "the trailing -1 is Workday's re-posting index, not part of the requisition id — "
                + "keeping it would make a re-posted requisition look like a new job"
        )
    }

    // MARK: - Registry and mapping

    func testEverySourceHasAStableDistinctID() {
        let ids = JobSources.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(JobSources.source(id: "workday")?.displayName, "Workday")
        XCTAssertNil(JobSources.source(id: "nope"))
    }

    /// A row with no usable key can't be deduped, so it would be re-ingested on every single sweep
    /// — dropping it is the lesser failure.
    func testARowWithNoUsableKeyIsDropped() {
        let role = GreenhouseJobBoard.OpenRole(
            id: "1", title: "Role", locationName: nil, absoluteURL: "not a url",
            updatedAt: nil, firstPublished: nil
        )
        XCTAssertNil(JobSourceTransport.posting(from: role, sourceID: "x", company: nil))
    }
}
