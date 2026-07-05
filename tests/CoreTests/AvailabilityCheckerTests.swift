import SwiftData

// swiftlint:disable force_unwrapping
import XCTest
@testable import JobhuntCore

// MARK: - MockURLProtocol

/// URLProtocol subclass for mocking HTTP responses in tests.
final class MockURLProtocol: URLProtocol {
    /// Map from URL string pattern → handler closure.
    static var handlers: [(String, (URLRequest) -> (HTTPURLResponse, Data))] = []

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let urlString = request.url?.absoluteString ?? ""
        for (pattern, handler) in MockURLProtocol.handlers where urlString.contains(pattern) {
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // Default: 200 OK with empty body.
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        handlers = []
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - FailingURLProtocol

/// URLProtocol subclass that always fails with URLError(.notConnectedToInternet).
final class FailingURLProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Helper

private func makeResponse(url: String, status: Int = 200, body: String = "") -> (HTTPURLResponse, Data) {
    let parsedURL = URL(string: url)!
    let resp = HTTPURLResponse(url: parsedURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    return (resp, Data(body.utf8))
}

// MARK: - URL normalization

final class AvailabilityCheckerNormalizationTests: XCTestCase {
    func testNormalizedURLStripsTrailingSlash() {
        let result = AvailabilityChecker.normalizedURL("https://example.com/job/1/")
        XCTAssertEqual(result?.absoluteString, "https://example.com/job/1")
    }

    func testNormalizedURLSortsQueryParams() {
        let result = AvailabilityChecker.normalizedURL("https://example.com/job?b=2&a=1")
        XCTAssertEqual(result?.absoluteString, "https://example.com/job?a=1&b=2")
    }

    func testNormalizedURLStripsFragment() {
        let result = AvailabilityChecker.normalizedURL("https://example.com/job/1#section")
        XCTAssertTrue(result?.absoluteString.contains("#") == false)
    }

    func testNormalizedURLReturnsNilForInvalidURL() {
        XCTAssertNil(AvailabilityChecker.normalizedURL("not a url at all///"))
    }
}

// MARK: - checkURL unit tests (port of availability.test.js)

final class AvailabilityCheckerCheckURLTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    // MARK: Status code detection

    func testReturnsGoneFor404() async throws {
        MockURLProtocol.handlers = [(
            "example.com/job/1",
            { _ in makeResponse(url: "https://example.com/job/1", status: 404, body: "not found") }
        )]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: "https://example.com/job/1")),
            title: "Engineer",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone"); return }
        XCTAssertTrue(reason.contains("404"), "reason should contain 404, got: \(reason)")
    }

    func testReturnsGoneFor410() async throws {
        MockURLProtocol.handlers = [(
            "example.com/job/2",
            { _ in makeResponse(url: "https://example.com/job/2", status: 410, body: "gone") }
        )]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: "https://example.com/job/2")),
            title: "Engineer",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone"); return }
        XCTAssertTrue(reason.contains("410"), "reason should contain 410, got: \(reason)")
    }

    // MARK: Body pattern detection

    func testReturnsGoneWhenBodyContainsGonePattern() async throws {
        MockURLProtocol.handlers = [("example.com/job/4", { _ in
            makeResponse(url: "https://example.com/job/4", status: 200, body: "sorry, this job is no longer available.")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: "https://example.com/job/4")),
            title: "Software Engineering Role Here",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone"); return }
        XCTAssertTrue(reason.hasPrefix("body:"), "reason should start with 'body:', got: \(reason)")
    }

    /// Built In keeps a removed posting at HTTP 200 with the job TITLE still rendered (breadcrumb +
    /// H1) plus a "Similar Jobs" list, so the status/redirect/title heuristics all pass — only the
    /// inline "Sorry, this job was removed at …" banner reveals it's gone. Regression for that miss.
    func testReturnsGoneForBuiltInRemovedBanner_at200WithTitlePresent() async throws {
        let title = "Senior Technical Program Manager FUB Engineering"
        let body = """
        <h1>\(title)</h1>
        <p>Sorry, this job was removed at 02:24 p.m. (PST) on Tuesday, Jun 23, 2026</p>
        <section>Similar Jobs</section>
        """
        MockURLProtocol.handlers = [("builtinseattle.com/job/", { _ in
            makeResponse(url: "https://builtinseattle.com/job/x/8696567", status: 200, body: body)
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: "https://builtinseattle.com/job/x/8696567")),
            title: title,
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone, got \(result)"); return }
        XCTAssertTrue(reason.contains("job was removed"), "reason should cite the banner, got: \(reason)")
    }

    // MARK: Body "gone" matcher — generalized regex families + false-positive guards

    /// Each of these is a removed/closed/expired posting kept at HTTP 200 with custom wording. The
    /// regex families (not literal phrases) should catch them so we don't add a literal per site.
    func testBodyGoneReason_matchesRemovalFamilies() {
        let goneBodies = [
            "sorry, this job was removed at 02:24 p.m. (pst) on tuesday", // built in
            "this position has been filled and is now closed", // <subject> has been filled
            "we're sorry, but this job posting has expired.", // <subject> posting has expired
            "we are no longer accepting applications for this role", // no longer accepting applications
            "unfortunately this posting is no longer available", // <subject> is no longer available
            "the requisition was closed by the hiring team", // <subject> was closed
            "error 404: job not found" // <subject> not found
        ]
        for body in goneBodies {
            XCTAssertNotNil(
                AvailabilityChecker.bodyGoneReason(body),
                "should be flagged gone: \(body)"
            )
        }
    }

    /// Live or unrelated copy that merely contains words like "no longer", "open", or "removed"
    /// elsewhere must NOT be flagged — the families are anchored to a job-subject noun + outcome.
    func testBodyGoneReason_ignoresLiveOrUnrelatedCopy() {
        let liveBodies = [
            "apply now — we are actively accepting applications for this role",
            "candidates no longer need a college degree to apply for this position",
            "this role offers no longer commutes thanks to fully remote work",
            "senior product manager. salary 180k. apply today.",
            "this job has great benefits and is open to all applicants"
        ]
        for body in liveBodies {
            XCTAssertNil(
                AvailabilityChecker.bodyGoneReason(body),
                "should NOT be flagged gone: \(body) → \(String(describing: AvailabilityChecker.bodyGoneReason(body)))"
            )
        }
    }

    // MARK: Redirect heuristics

    func testGoneWhenRedirectedToCompanyPage() async throws {
        let originalURL = "https://www.builtinseattle.com/job/technical-program-manager/123"
        let finalURL = "https://www.builtinseattle.com/company/deepgram"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: finalURL, status: 200, body: "Deepgram Seattle Office: Careers, Perks + Culture")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Technical Program Manager",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone"); return }
        XCTAssertTrue(reason.contains("redirected to non-job page"), "reason: \(reason)")
    }

    func testGoneWhenRedirectedAndMissingTitle() async throws {
        let originalURL = "https://jobs.example.com/postings/123"
        let finalURL = "https://jobs.example.com/postings/456"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: finalURL, status: 200, body: "Senior Product Manager Apply now")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Principal Technical Program Manager",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone"); return }
        XCTAssertTrue(reason.contains("missing title"), "reason: \(reason)")
    }

    // MARK: - Greenhouse expired posting + http→https upgrade (TASK-594)

    /// The concrete job-37 case: an expired Greenhouse posting captured as a plain `http://` URL.
    /// The checker must upgrade the request to https (else ATS blocks it and it's never checked), then
    /// recognize the `…/{board}?error=true` landing Greenhouse redirects removed postings to.
    func testGreenhouseExpiredPosting_httpURL_isGone() async throws {
        let httpURL = "http://job-boards.greenhouse.io/gitlab/jobs/8509676002"
        let boardError = "https://job-boards.greenhouse.io/gitlab?error=true"
        MockURLProtocol.handlers = [("job-boards.greenhouse.io/gitlab/jobs", { request in
            // The request must have been upgraded to https before hitting the network.
            XCTAssertEqual(request.url?.scheme, "https", "http request URL must be upgraded to https")
            return makeResponse(url: boardError, status: 200, body: "GitLab is hiring. View all jobs.")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: httpURL)),
            title: "Senior Director, Technical Program Management",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone"); return }
        XCTAssertTrue(reason.contains("board posting not found"), "reason: \(reason)")
    }

    func testHTTPSUpgrade_onlyRewritesPlainHTTP() throws {
        let httpURL = try XCTUnwrap(URL(string: "http://x.com/a?b=1"))
        XCTAssertEqual(AvailabilityChecker.httpsUpgraded(httpURL).absoluteString, "https://x.com/a?b=1")
        // Already-secure and non-http(s) schemes are untouched.
        let httpsURL = try XCTUnwrap(URL(string: "https://x.com/a"))
        XCTAssertEqual(AvailabilityChecker.httpsUpgraded(httpsURL).absoluteString, "https://x.com/a")
    }

    func testBoardErrorLanding_detectsGreenhouseErrorQueryOnly() {
        XCTAssertTrue(AvailabilityChecker.isBoardErrorLandingURL("https://job-boards.greenhouse.io/gitlab?error=true"))
        XCTAssertTrue(AvailabilityChecker.isBoardErrorLandingURL("https://boards.greenhouse.io/acme?error=true"))
        // A live Greenhouse posting URL (no error query) is NOT a landing page.
        XCTAssertFalse(AvailabilityChecker.isBoardErrorLandingURL("https://job-boards.greenhouse.io/gitlab/jobs/123"))
        // error=true on a non-Greenhouse host doesn't trigger it (avoid over-broad matching).
        XCTAssertFalse(AvailabilityChecker.isBoardErrorLandingURL("https://example.com/jobs?error=true"))
    }

    // MARK: - Multi-ATS gone-landing generalization + LinkedIn closed-job banner

    func testBoardErrorLanding_detectsWorkableOopsLanding() {
        // Workable 302-redirects a removed/unknown posting to `/oops` (HTTP 200).
        XCTAssertTrue(AvailabilityChecker.isBoardErrorLandingURL("https://apply.workable.com/oops"))
        // A live Workable posting path is NOT the oops landing.
        XCTAssertFalse(AvailabilityChecker.isBoardErrorLandingURL("https://apply.workable.com/acme/j/ABC123/"))
        // `/oops` on a non-Workable host doesn't trigger it.
        XCTAssertFalse(AvailabilityChecker.isBoardErrorLandingURL("https://example.com/oops"))
    }

    /// End-to-end: a removed Workable posting redirects to `/oops` at HTTP 200 — status/body/redirect
    /// heuristics all miss it, so the board-landing rule must flag it gone.
    func testWorkableRemovedPosting_redirectsToOops_isGone() async throws {
        let original = "https://apply.workable.com/acme/j/ABC123/"
        let oops = "https://apply.workable.com/oops"
        MockURLProtocol.handlers = [("apply.workable.com/acme/j", { _ in
            makeResponse(url: oops, status: 200, body: "Oops, we couldn't find that page.")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: original)),
            title: "Principal Product Manager Remote",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone, got \(result)"); return }
        XCTAssertTrue(reason.contains("board posting not found"), "reason: \(reason)")
    }

    /// Job #130: LinkedIn's public guest view renders a structured `closed-job` banner for a posting no
    /// longer accepting applications, at HTTP 200 with no redirect. Uses non-English banner text (no
    /// literal "no longer accepting applications") to prove the structural class — not the phrase — is
    /// what trips detection.
    func testLinkedInClosedJobBanner_isGone_evenWithoutEnglishPhrase() async throws {
        let url = "https://www.linkedin.com/jobs/view/4424422798/"
        let body = """
        <figure class="closed-job closed-job__flavor topcard__flavor-row">
          <span class="closed-job__icon"></span>
          <figcaption class="closed-job__flavor--closed">Não aceita mais candidaturas</figcaption>
        </figure>
        """
        MockURLProtocol.handlers = [("linkedin.com/jobs/view/4424422798", { _ in
            makeResponse(url: url, status: 200, body: body)
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)),
            title: "Principal Product Manager Remote",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone, got \(result)"); return }
        XCTAssertTrue(reason.contains("closed-job"), "reason should cite the banner, got: \(reason)")
    }

    /// A live LinkedIn guest posting (Apply CTA, no `closed-job` markup) must stay available — the
    /// structural marker must not false-positive on an open job.
    func testLinkedInLiveGuestView_isAvailable() async throws {
        let url = "https://www.linkedin.com/jobs/view/999999/"
        MockURLProtocol.handlers = [("linkedin.com/jobs/view/999999", { _ in
            makeResponse(
                url: url,
                status: 200,
                body: "<h1>Principal Product Manager Remote</h1><button>Apply</button> Actively recruiting"
            )
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)),
            title: "Principal Product Manager Remote",
            session: session
        )
        if case let .gone(reason) = result { XCTFail("Expected .available, got .gone(\(reason))") }
    }

    /// The `closed-job` class is LinkedIn markup; the same class on a non-LinkedIn host must NOT be
    /// treated as gone (host-scoped to avoid over-broad matching).
    func testClosedJobMarkupOnNonLinkedInHost_isNotGone() {
        XCTAssertFalse(AvailabilityChecker.isLinkedInClosedJob(
            finalURLString: "https://example.com/jobs/view/1",
            body: "<figcaption class=\"closed-job__flavor--closed\">no longer accepting applications</figcaption>"
        ))
        XCTAssertTrue(AvailabilityChecker.isLinkedInClosedJob(
            finalURLString: "https://www.linkedin.com/jobs/view/1",
            body: "<figure class=\"closed-job closed-job__flavor\">"
        ))
    }

    func testLinkedInLoginRedirectIsNotGone() async throws {
        // LinkedIn redirects an un-authenticated check to a generic collections page that lacks the
        // job title — a login wall, not a removed listing. Must be treated as available.
        let originalURL = "https://www.linkedin.com/jobs/view/4415725485"
        let finalURL = "https://www.linkedin.com/jobs/collections/similar-jobs/?currentJobId=4415725485"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: finalURL, status: 200, body: "See similar jobs on LinkedIn. Sign in.")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "AI Product Manager Remote",
            session: session
        )
        if case let .gone(reason) = result { XCTFail("Expected .available, got .gone(\(reason))") }
    }

    func testGenericLoginRedirectIsNotGone() async throws {
        let originalURL = "https://careers.example.com/postings/789"
        let finalURL = "https://careers.example.com/account/login?next=/postings/789"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: finalURL, status: 200, body: "Please sign in to continue.")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Staff Program Manager Operations",
            session: session
        )
        if case let .gone(reason) = result { XCTFail("Expected .available, got .gone(\(reason))") }
    }

    func testLinkedIn404StillGone() async throws {
        // A real 404 must still be flagged even on LinkedIn (status check precedes the auth-wall guard).
        let originalURL = "https://www.linkedin.com/jobs/view/999"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: originalURL, status: 404, body: "")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Whatever Role Here",
            session: session
        )
        guard case .gone = result else { XCTFail("Expected .gone for 404"); return }
    }

    func testAvailableWhenCanonicalRedirectHasTitle() async throws {
        let originalURL = "https://jobs.example.com/postings/123?src=board"
        let finalURL = "https://jobs.example.com/postings/123"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: finalURL, status: 200, body: "Principal Technical Program Manager Apply now")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Principal Technical Program Manager",
            session: session
        )
        if case let .gone(goneReason) = result { XCTFail("Expected .available but got .gone(\(goneReason))") }
    }

    func testGoneWhenRedirectedToSearchPage() async throws {
        let originalURL = "https://careers.example.com/jobs/postings/456"
        let finalURL = "https://careers.example.com/careers/search"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: finalURL, status: 200, body: "Data Engineer posting here")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Data Engineer",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone"); return }
        XCTAssertTrue(reason.contains("redirected"), "reason: \(reason)")
    }

    func testAvailableForCrossDomainRedirectWithTitle() async throws {
        let originalURL = "https://board.example.com/job/123"
        let finalURL = "https://company.example.org/jobs/123"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: finalURL, status: 200, body: "Senior Software Engineer Role open position apply now")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Senior Software Engineer Role",
            session: session
        )
        if case let .gone(goneReason) = result { XCTFail("Expected .available but got .gone(\(goneReason))") }
    }

    func testGoneForLevelsFyiJobsPageRedirect() async throws {
        let originalURL = "https://www.levels.fyi/jobs/title/technical-program-manager?jobId=138073367340032710"
        let finalURL = "https://www.levels.fyi/jobs/title/technical-program-manager"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: finalURL, status: 200, body: "Technical Program Manager Jobs Search filters")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Sr. Staff Technical Program Manager - DoW",
            session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone"); return }
        XCTAssertTrue(reason.contains("missing title"), "reason: \(reason)")
    }

    // MARK: Error handling

    func testReturnsErrorOnNetworkFailure() async throws {
        let failingSession = FailingURLProtocol.makeSession()
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: "https://example.com/job/999")),
            title: "Some Job",
            session: failingSession
        )
        guard case let .error(error) = result else {
            XCTFail("Expected .error but got \(result)")
            return
        }
        let urlError = error as? URLError
        XCTAssertEqual(urlError?.code, .notConnectedToInternet, "Should propagate URLError(.notConnectedToInternet)")
    }
}

// MARK: - redirectedToNonJobPage unit tests

final class AvailabilityCheckerRedirectTests: XCTestCase {
    func testSameURLNotRedirected() {
        XCTAssertFalse(AvailabilityChecker.redirectedToNonJobPage(
            originalURLString: "https://example.com/job/1",
            finalURLString: "https://example.com/job/1"
        ))
    }

    func testRedirectToRootIsGone() {
        XCTAssertTrue(AvailabilityChecker.redirectedToNonJobPage(
            originalURLString: "https://example.com/job/1",
            finalURLString: "https://example.com/"
        ))
    }

    func testRedirectToJobsRootIsGone() {
        XCTAssertTrue(AvailabilityChecker.redirectedToNonJobPage(
            originalURLString: "https://example.com/job/123",
            finalURLString: "https://example.com/jobs"
        ))
    }

    func testRedirectToCompanyPageIsGone() {
        XCTAssertTrue(AvailabilityChecker.redirectedToNonJobPage(
            originalURLString: "https://builtinseattle.com/job/123",
            finalURLString: "https://builtinseattle.com/company/deepgram"
        ))
    }

    func testCrossDomainRedirectIsNotGone() {
        XCTAssertFalse(AvailabilityChecker.redirectedToNonJobPage(
            originalURLString: "https://board.com/job/1",
            finalURLString: "https://company.com/jobs/search"
        ))
    }

    func testInvalidOriginalURLReturnsFalse() {
        XCTAssertFalse(AvailabilityChecker.redirectedToNonJobPage(
            originalURLString: "not-a-valid-url",
            finalURLString: "https://different.example.com/other-page"
        ))
    }
}

// MARK: - isMeaningfulTitle

final class AvailabilityCheckerAuthWallTests: XCTestCase {
    func testLinkedInCollectionsIsAuthWall() {
        XCTAssertTrue(AvailabilityChecker.isAuthWallURL(
            "https://www.linkedin.com/jobs/collections/similar-jobs/?currentJobId=123"
        ))
    }

    func testGenericLoginPathsAreAuthWall() {
        XCTAssertTrue(AvailabilityChecker.isAuthWallURL("https://careers.example.com/account/login?next=/x"))
        XCTAssertTrue(AvailabilityChecker.isAuthWallURL("https://example.com/authwall"))
        XCTAssertTrue(AvailabilityChecker.isAuthWallURL("https://example.com/sign-in"))
    }

    func testNormalJobURLIsNotAuthWall() {
        XCTAssertFalse(AvailabilityChecker.isAuthWallURL("https://boards.example.com/postings/123"))
        XCTAssertFalse(AvailabilityChecker.isAuthWallURL("https://www.linkedin.com/jobs/view/4415725485"))
    }
}

final class AvailabilityCheckerTitleTests: XCTestCase {
    func testShortTitleNotMeaningful() {
        XCTAssertFalse(AvailabilityChecker.isMeaningfulTitle("Engineer"))
    }

    func testThreeWordTitleIsMeaningful() {
        XCTAssertTrue(AvailabilityChecker.isMeaningfulTitle("Software Engineering Role"))
    }

    func testEmptyTitleNotMeaningful() {
        XCTAssertFalse(AvailabilityChecker.isMeaningfulTitle(""))
    }

    func testBodyContainsTitleReturnsTrueForShortTitle() {
        // Short titles skip the body check → always return true.
        XCTAssertTrue(AvailabilityChecker.bodyContainsTitle("completely different content", title: "Engineer"))
    }

    func testBodyContainsTitleWorksForLongTitle() {
        XCTAssertTrue(AvailabilityChecker.bodyContainsTitle(
            "Principal Technical Program Manager Apply now", title: "Principal Technical Program Manager"
        ))
        XCTAssertFalse(AvailabilityChecker.bodyContainsTitle(
            "Senior Product Manager Apply now", title: "Principal Technical Program Manager"
        ))
    }
}

// MARK: - checkJobs with BackgroundStore

final class AvailabilityCheckerJobsTests: XCTestCase {
    var container: ModelContainer!
    var store: BackgroundStore!
    var session: URLSession!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        store = BackgroundStore(modelContainer: container)
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    override func tearDown() async throws {
        container = nil
        store = nil
    }

    func makeJobWithCapture(
        url: String,
        title: String,
        status: JobStatus = .pursuing,
        capturedAt: Date = Date()
    ) throws -> Job {
        let context = ModelContext(container)
        let capture = Capture(url: url, pageTitle: title, rawHash: UUID().uuidString, capturedAt: capturedAt)
        let job = Job(title: title, status: status)
        job.capture = capture
        job.capturedAtDenormalized = capturedAt
        context.insert(capture)
        context.insert(job)
        try context.save()
        return job
    }

    func testCheckJobsReturnsZeroForNoJobs() async {
        let result = await AvailabilityChecker.checkJobs([], store: store, session: session)
        XCTAssertEqual(result.checked, 0)
        XCTAssertEqual(result.unavailable, 0)
        XCTAssertEqual(result.marked, 0)
    }

    func testCheckJobsSkipsArchivedAndNotAvailable() async throws {
        let archived = try makeJobWithCapture(
            url: "https://example.com/job/a",
            title: "Archived Job",
            status: .passed
        )
        let notAvail = try makeJobWithCapture(
            url: "https://example.com/job/b",
            title: "Not Available Job",
            status: .closed
        )

        let result = await AvailabilityChecker.checkJobs([archived, notAvail], store: store, session: session)
        XCTAssertEqual(result.checked, 0) // All skipped.
    }

    func testCheckJobsMarksGoneJobAsNotAvailable() async throws {
        MockURLProtocol.handlers = [
            (
                "check-gone.example.com",
                { _ in makeResponse(url: "https://check-gone.example.com/job/2", status: 404, body: "not found") }
            ),
            (
                "check-available.example.com",
                { _ in makeResponse(
                    url: "https://check-available.example.com/job/1",
                    status: 200,
                    body: "Job posting available"
                ) }
            )
        ]

        let goodJob = try makeJobWithCapture(url: "https://check-available.example.com/job/1", title: "Good Job")
        let goneJob = try makeJobWithCapture(url: "https://check-gone.example.com/job/2", title: "Gone Job")

        var receivedNotification = false
        let obs = NotificationCenter.default.addObserver(
            forName: .jobUnavailable, object: nil, queue: nil
        ) { _ in receivedNotification = true }
        defer { NotificationCenter.default.removeObserver(obs) }

        let result = await AvailabilityChecker.checkJobs([goodJob, goneJob], store: store, session: session)
        XCTAssertEqual(result.checked, 2)
        XCTAssertEqual(result.unavailable, 1)
        XCTAssertEqual(result.marked, 1)
        XCTAssertTrue(receivedNotification)
    }

    func testCheckStaleJobsOnlyChecksStaleJobs() async throws {
        // Stale job (captured 30 days ago).
        let staleDate = Date().addingTimeInterval(-30 * 86400)
        MockURLProtocol.handlers = [
            (
                "stale.example.com",
                { _ in makeResponse(url: "https://stale.example.com/job/1", status: 404, body: "gone") }
            )
        ]

        let staleJob = try makeJobWithCapture(
            url: "https://stale.example.com/job/1",
            title: "Stale Job",
            capturedAt: staleDate
        )
        let freshJob = try makeJobWithCapture(
            url: "https://fresh.example.com/job/2",
            title: "Fresh Job",
            capturedAt: Date()
        )

        let result = try await AvailabilityChecker.checkStaleJobs(
            store: store,
            staleDays: 21,
            limit: 10,
            session: session
        )

        // Only the stale job should be checked.
        XCTAssertEqual(result.checked, 1, "Only stale job should be checked")
        XCTAssertEqual(result.unavailable, 1)
        _ = freshJob // Suppress unused warning — it should NOT be checked.
        _ = staleJob
    }

    /// AC#3 for TASK-147: active stale jobs must be found even when many earlier-created jobs are archived.
    /// The old limit*10 over-fetch could miss active jobs if archived jobs filled the fetch window.
    func testCheckStaleJobs_findsActiveJobsBeyondArchivedWindow() async throws {
        let staleDate = Date().addingTimeInterval(-30 * 86400)

        // Create many archived stale jobs that would fill a limit*10 fetch window.
        for i in 0 ..< 15 {
            let archivedDate = staleDate.addingTimeInterval(-Double(i) * 3600)
            _ = try makeJobWithCapture(
                url: "https://archived.example.com/job/\(i)",
                title: "Archived Job \(i)",
                status: .archived,
                capturedAt: archivedDate
            )
        }

        // Active stale job created after the archived block.
        MockURLProtocol.handlers = [(
            "active-stale.example.com",
            { _ in makeResponse(url: "https://active-stale.example.com/job/active", status: 200, body: "still open") }
        )]
        _ = try makeJobWithCapture(
            url: "https://active-stale.example.com/job/active",
            title: "Active Stale Job",
            status: .pursuing,
            capturedAt: staleDate
        )

        let result = try await AvailabilityChecker.checkStaleJobs(
            store: store,
            staleDays: 21,
            limit: 5,
            session: session
        )

        XCTAssertEqual(
            result.checked,
            1,
            "Active stale job must be checked even when earlier archived jobs fill the window"
        )
    }

    func testMaybeRunStaleCheckSkipsWhenDisabled() async {
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        settings.setBool(false, forKey: SettingsKey.availabilityAutoCheckEnabled)

        let result = await AvailabilityChecker.maybeRunStaleCheck(store: store, settings: settings, session: session)
        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.reason, "disabled")
    }

    func testMaybeRunStaleCheckSkipsWhenIntervalNotElapsed() async {
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        settings.setBool(true, forKey: SettingsKey.availabilityAutoCheckEnabled)
        // Set last check to now → interval hasn't elapsed.
        settings.set(ISO8601DateFormatter().string(from: Date()), forKey: SettingsKey.availabilityLastAutoCheckAt)

        let result = await AvailabilityChecker.maybeRunStaleCheck(store: store, settings: settings, session: session)
        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.reason, "interval")
    }

    func testMaybeRunStaleCheckRunsWhenEnabledAndIntervalElapsed() async {
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        settings.setBool(true, forKey: SettingsKey.availabilityAutoCheckEnabled)
        // Last check was a long time ago.
        settings.set("2020-01-01T00:00:00Z", forKey: SettingsKey.availabilityLastAutoCheckAt)

        let result = await AvailabilityChecker.maybeRunStaleCheck(store: store, settings: settings, session: session)
        XCTAssertFalse(result.skipped)
        XCTAssertNil(result.reason)
        // checked is a number (could be 0 if no stale jobs).
        XCTAssertGreaterThanOrEqual(result.checked, 0)
        XCTAssertEqual(result.failed, 0, "No per-job marking failures expected on a clean store")
    }

    /// Records the completion date the checker hands to the explicit callback.
    private actor CompletionRecorder {
        private(set) var date: Date?
        private(set) var callCount = 0
        func record(_ d: Date) {
            date = d; callCount += 1
        }
    }

    /// TASK-428/389 AC#2/#4: the last-check timestamp is advanced only after a valid pass, delivered
    /// through the explicit `onAutoCheckCompleted` callback (no global notification observer).
    func testMaybeRunStaleCheck_invokesCompletionCallbackOnSuccessfulPass() async {
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        settings.setBool(true, forKey: SettingsKey.availabilityAutoCheckEnabled)
        settings.set("2020-01-01T00:00:00Z", forKey: SettingsKey.availabilityLastAutoCheckAt)

        let recorder = CompletionRecorder()
        let result = await AvailabilityChecker.maybeRunStaleCheck(
            store: store, settings: settings, session: session,
            onAutoCheckCompleted: { await recorder.record($0) }
        )
        XCTAssertFalse(result.skipped)
        XCTAssertNil(result.reason, "A successful pass must not report a fetch-error reason")

        let count = await recorder.callCount
        let date = await recorder.date
        XCTAssertEqual(count, 1, "callback must fire exactly once on a valid pass")
        XCTAssertNotNil(date, "callback must carry the completion timestamp")
    }

    func testMaybeRunStaleCheck_fetchFailure_doesNotAdvanceTimestamp() async {
        // TASK-479/389 AC#4: a store fetch failure must surface as fetch-error and NOT invoke the
        // completion callback (so the interval gate isn't advanced without a real check).
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        settings.setBool(true, forKey: SettingsKey.availabilityAutoCheckEnabled)
        settings.set("2020-01-01T00:00:00Z", forKey: SettingsKey.availabilityLastAutoCheckAt)
        struct FakeStoreError: Error {}
        await store.setFetchFault(FakeStoreError())

        let recorder = CompletionRecorder()
        let result = await AvailabilityChecker.maybeRunStaleCheck(
            store: store, settings: settings, session: session,
            onAutoCheckCompleted: { await recorder.record($0) }
        )

        XCTAssertFalse(result.skipped, "a fetch failure is a failed pass, not a skip")
        XCTAssertEqual(result.reason, "fetch-error")
        let count = await recorder.callCount
        XCTAssertEqual(count, 0, "fetch failure must not advance the last-check timestamp")
    }

    func testMaybeRunStaleCheck_skipped_doesNotInvokeCompletionCallback() async {
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        // Auto-check disabled → skipped → callback must NOT fire (interval gate must not advance).
        settings.setBool(false, forKey: SettingsKey.availabilityAutoCheckEnabled)

        let recorder = CompletionRecorder()
        let result = await AvailabilityChecker.maybeRunStaleCheck(
            store: store, settings: settings, session: session,
            onAutoCheckCompleted: { await recorder.record($0) }
        )
        XCTAssertTrue(result.skipped)
        let count = await recorder.callCount
        XCTAssertEqual(count, 0, "skipped check must not advance the last-check timestamp")
    }
}

// swiftlint:enable force_unwrapping
