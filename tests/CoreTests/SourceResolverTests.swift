import Foundation
import XCTest
@testable import JobhuntCore

/// Finding a company's board from its name, or from a pasted URL (TASK-694, M5).
///
/// Two things are being defended here. One is usability — a user who doesn't know what a Greenhouse
/// board slug is has to be able to add a source. The other is that a company name becomes part of a
/// URL, which makes slug construction the SSRF choke point.
final class SourceResolverTests: XCTestCase {
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

    private func greenhouseBoard(count: Int) -> String {
        let jobs = (1 ... max(1, count)).map { index in
            """
            { "id": \(index), "title": "Role \(index)",
              "absolute_url": "https://boards.greenhouse.io/acme/jobs/\(index)",
              "location": { "name": "Remote" } }
            """
        }.joined(separator: ",")
        return #"{ "jobs": [\#(count == 0 ? "" : jobs)] }"#
    }

    // MARK: - Slug derivation

    func testACompanyNameBecomesASlug() {
        XCTAssertEqual(SourceResolver.deriveSlug("Acme Corp, Inc."), "acme-corp-inc")
        XCTAssertEqual(SourceResolver.deriveSlug("GitLab"), "gitlab")
        XCTAssertEqual(SourceResolver.deriveSlug("  1Password  "), "1password")
    }

    /// The SSRF choke point. A company name reaches a URL, so anything that could change the host
    /// has to be gone before interpolation — and the built URL is re-parsed to confirm it.
    func testASlugCanNeverChangeTheHost() {
        for hostile in [
            "evil.com/../..", "acme@evil.com", "acme#@evil.com",
            "acme/jobs", "acme?x=1", "acme:8080"
        ] {
            let derived = SourceResolver.deriveSlug(hostile)
            XCTAssertTrue(
                SourceResolver.isSafeSlug(derived),
                "derivation should have neutralised “\(hostile)” → “\(derived)”"
            )
            let candidate = SourceResolver.candidate(kind: "greenhouse", slug: derived)
            let host = candidate.flatMap { URL(string: $0.boardURL)?.host }
            XCTAssertEqual(host, "job-boards.greenhouse.io", hostile)
        }
    }

    /// A raw slug that skipped derivation must still be refused rather than interpolated.
    func testAnUnsafeRawSlugIsRefusedOutright() {
        XCTAssertFalse(SourceResolver.isSafeSlug("acme/evil"))
        XCTAssertFalse(SourceResolver.isSafeSlug("acme@evil.com"))
        XCTAssertFalse(SourceResolver.isSafeSlug(""))
        XCTAssertNil(SourceResolver.candidate(kind: "greenhouse", slug: "acme/evil"))
    }

    func testANameWithNothingUsableFails() async {
        let result = await SourceResolver.resolve(
            companyName: "!!!", session: MockURLProtocol.makeSession()
        )
        guard case .failed(.unusableName) = result else {
            return XCTFail("expected .unusableName, got \(result)")
        }
    }

    // MARK: - Resolving by name

    func testACompanyResolvesToItsBoard() async {
        stub("boards-api.greenhouse.io", body: greenhouseBoard(count: 3))
        let result = await SourceResolver.resolve(
            companyName: "Acme", session: MockURLProtocol.makeSession()
        )
        guard case let .resolved(board) = result else { return XCTFail("expected a board, got \(result)") }
        XCTAssertEqual(board.kind, "greenhouse")
        XCTAssertEqual(board.slug, "acme")
        XCTAssertEqual(board.jobCount, 3)
        XCTAssertEqual(board.boardURL, "https://job-boards.greenhouse.io/acme")
    }

    /// The rule that makes the whole thing trustworthy: a URL that merely fails to 404 is not a
    /// resolution. Saving one is exactly how dead slugs get in, and a dead slug looks identical to a
    /// company that stopped hiring.
    func testABoardWithNoJobsIsNotAResolution() async {
        stub("boards-api.greenhouse.io", body: greenhouseBoard(count: 0))
        stub("api.ashbyhq.com", status: 404, body: "")
        stub("api.lever.co", status: 404, body: "")

        let result = await SourceResolver.resolve(
            companyName: "Acme", session: MockURLProtocol.makeSession()
        )
        guard case let .failed(.boardsFoundButEmpty(boards)) = result else {
            return XCTFail("expected .boardsFoundButEmpty, got \(result)")
        }
        XCTAssertEqual(boards.first?.kind, "greenhouse", "the empty board is still worth offering")
    }

    /// First hit wins, so a company that resolves on Greenhouse never sends a request to Ashby or
    /// Lever.
    func testProbingStopsAtTheFirstMatch() async {
        stub("boards-api.greenhouse.io", body: greenhouseBoard(count: 2))
        stub("api.ashbyhq.com", body: "SHOULD NOT BE REACHED")
        let result = await SourceResolver.resolve(
            companyName: "Acme", session: MockURLProtocol.makeSession()
        )
        guard case let .resolved(board) = result else { return XCTFail("expected a board") }
        XCTAssertEqual(board.kind, "greenhouse")
    }

    func testAVendorMissFallsThroughToTheNext() async {
        stub("boards-api.greenhouse.io", status: 404, body: "")
        stub("api.ashbyhq.com", body: """
        { "jobs": [ { "id": "1", "title": "Role", "jobUrl": "https://jobs.ashbyhq.com/acme/1",
          "location": "Remote", "isListed": true } ] }
        """)
        let result = await SourceResolver.resolve(
            companyName: "Acme", session: MockURLProtocol.makeSession()
        )
        guard case let .resolved(board) = result else { return XCTFail("expected a board, got \(result)") }
        XCTAssertEqual(board.kind, "ashby")
    }

    func testEveryVendorSayingNoIsNoBoardFound() async {
        for pattern in ["boards-api.greenhouse.io", "api.ashbyhq.com", "api.lever.co"] {
            stub(pattern, status: 404, body: "")
        }
        let result = await SourceResolver.resolve(
            companyName: "Nobody", session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(result, .failed(.noBoardFound))
    }

    /// A probe that never answered leaves absence unestablished, so "no board found" would be a
    /// claim we can't make — and it sends the user to fix the wrong thing.
    func testAProbeThatCouldNotAnswerIsInconclusiveNotAbsent() async {
        stub("boards-api.greenhouse.io", status: 503, body: "")
        stub("api.ashbyhq.com", status: 404, body: "")
        stub("api.lever.co", status: 404, body: "")

        let result = await SourceResolver.resolve(
            companyName: "Acme", session: MockURLProtocol.makeSession()
        )
        guard case .failed(.inconclusive) = result else {
            return XCTFail("expected .inconclusive, got \(result)")
        }
    }

    // MARK: - Identifying a pasted URL

    /// The other half of usability: a user who can't name their ATS can still paste the address of
    /// the page they're looking at.
    func testAPastedURLIsIdentifiedWithoutANetworkCall() throws {
        let greenhouse = try XCTUnwrap(
            SourceResolver.identify(boardURL: "https://job-boards.greenhouse.io/gitlab")
        )
        XCTAssertEqual(greenhouse.kind, "greenhouse")
        XCTAssertEqual(greenhouse.slug, "gitlab")

        let lever = try XCTUnwrap(SourceResolver.identify(boardURL: "https://jobs.lever.co/netflix"))
        XCTAssertEqual(lever.kind, "lever")

        let ashby = try XCTUnwrap(SourceResolver.identify(boardURL: "https://jobs.ashbyhq.com/ramp"))
        XCTAssertEqual(ashby.kind, "ashby")
    }

    /// A posting deep link is at least as likely to be in the clipboard as a board landing page.
    func testAPostingDeepLinkIdentifiesItsBoard() throws {
        let board = try XCTUnwrap(SourceResolver.identify(
            boardURL: "https://job-boards.greenhouse.io/gitlab/jobs/8658878002"
        ))
        XCTAssertEqual(board.slug, "gitlab")
    }

    /// Workday is the reason this entry point exists at all: no rule turns "Acme" into `acme.wd5`,
    /// so the URL is the only way in.
    func testAWorkdayURLIsIdentifiedAndKeepsItsWholeAddress() throws {
        let board = try XCTUnwrap(SourceResolver.identify(
            boardURL: "https://acme.wd5.myworkdayjobs.com/en-US/careers"
        ))
        XCTAssertEqual(board.kind, "workday")
        XCTAssertEqual(
            board.slug, "https://acme.wd5.myworkdayjobs.com/en-US/careers",
            "Workday keeps its whole config in the URL, so the slug IS the URL"
        )
    }

    func testAnUnrecognisedURLIsNotIdentified() {
        XCTAssertNil(SourceResolver.identify(boardURL: "https://example.com/careers"))
        XCTAssertNil(SourceResolver.identify(boardURL: "not a url at all"))
        XCTAssertNil(SourceResolver.identify(boardURL: "https://job-boards.greenhouse.io"))
    }

    func testAPastedURLIsVerifiedBeforeItResolves() async {
        stub("boards-api.greenhouse.io", body: greenhouseBoard(count: 4))
        let result = await SourceResolver.resolve(
            boardURL: "https://job-boards.greenhouse.io/acme", session: MockURLProtocol.makeSession()
        )
        guard case let .resolved(board) = result else { return XCTFail("expected a board, got \(result)") }
        XCTAssertEqual(board.jobCount, 4)
    }

    // MARK: - Re-resolution

    /// Three empty runs can also mean the company paused hiring. Re-probing the current board first
    /// means a pause doesn't get "fixed" by repointing the source at a different vendor.
    func testReresolutionKeepsAWorkingBoard() async {
        stub("boards-api.greenhouse.io", body: greenhouseBoard(count: 7))
        let result = await SourceResolver.reresolve(
            currentKind: "greenhouse", currentSlug: "acme", companyName: "Acme",
            session: MockURLProtocol.makeSession()
        )
        guard case let .resolved(board) = result else { return XCTFail("expected a board") }
        XCTAssertEqual(board.slug, "acme")
        XCTAssertEqual(board.jobCount, 7)
    }

    /// The case this exists for: the board migrated. career-ops saw 13 of 87 boards move, and
    /// re-resolution recovered 8 — one going from 0 to 53 open roles.
    func testReresolutionFindsAMigratedBoardOnAnotherVendor() async {
        stub("boards-api.greenhouse.io", status: 404, body: "")
        stub("api.ashbyhq.com", body: """
        { "jobs": [ { "id": "1", "title": "Role", "jobUrl": "https://jobs.ashbyhq.com/acme/1",
          "location": "Remote", "isListed": true } ] }
        """)
        let result = await SourceResolver.reresolve(
            currentKind: "greenhouse", currentSlug: "acme", companyName: "Acme",
            session: MockURLProtocol.makeSession()
        )
        guard case let .resolved(board) = result else { return XCTFail("expected a board, got \(result)") }
        XCTAssertEqual(board.kind, "ashby", "the source can be repointed at where the board went")
    }
}

/// Repointing a source after re-resolution (TASK-694, M5).
final class SearchSourceRepairTests: XCTestCase {
    /// The health counters describe the board the source *used* to point at. Leaving them would keep
    /// the "may have moved" warning on a source that was just repaired.
    func testRepointingClearsTheHealthCountersAndRunsImmediately() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let source = SearchSource(
            kind: "greenhouse", label: "Acme", config: SourceConfig(slug: "acme", company: "Acme")
        )
        try await store.insert(source)
        for _ in 1 ... 3 {
            try await store.recordSearchSourceRun(id: source.id, status: .empty)
        }
        let before: [SearchSource] = try await store.searchSources()
        XCTAssertTrue(try XCTUnwrap(before.first).looksMigrated)

        try await store.updateSearchSourceConfig(
            id: source.id, kind: "ashby", config: SourceConfig(slug: "acme", company: "Acme")
        )

        let all: [SearchSource] = try await store.searchSources()
        let after = try XCTUnwrap(all.first)
        XCTAssertEqual(after.kind, "ashby")
        XCTAssertEqual(after.consecutiveEmptyRuns, 0)
        XCTAssertFalse(after.looksMigrated)
        XCTAssertNil(after.lastError)
        XCTAssertTrue(after.isDue(), "the user should see whether the repair worked, not wait a cycle")
    }
}
