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

    /// TASK-626 (job #325 Cribl): bare "page not found" appears in the STATIC HTML shell of JS-rendered
    /// career sites (Greenhouse `gh_jid` pages) even for LIVE jobs, so it must not be a gone signal.
    /// The job-scoped "job not found" family still is.
    func testBodyGoneReason_barePageNotFound_isNotGone() {
        XCTAssertNil(
            AvailabilityChecker.bodyGoneReason("<title>Page not found</title><div>404 page not found</div>"),
            "bare 'page not found' must not be flagged gone (JS-shell false positive)"
        )
        XCTAssertNotNil(
            AvailabilityChecker.bodyGoneReason("this job not found in our system"),
            "job-scoped 'job not found' must still be gone"
        )
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

    // MARK: Workday CXS detection (job #119)

    func testWorkdayCXSQuery_parsesTenantSiteAndReqId() throws {
        let url = try XCTUnwrap(URL(string:
            "https://zillow.wd5.myworkdayjobs.com/en-US/Zillow_Group_External/job/Senior-TPM_P750186-2"))
        let cxs = try XCTUnwrap(AvailabilityChecker.workdayCXSQuery(for: url))
        XCTAssertEqual(
            cxs.endpoint.absoluteString,
            "https://zillow.wd5.myworkdayjobs.com/wday/cxs/zillow/Zillow_Group_External/jobs"
        )
        XCTAssertEqual(cxs.reqId, "P750186")
    }

    func testWorkdayCXSQuery_nonWorkdayHost_isNil() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/job/Some-Role_P1"))
        XCTAssertNil(AvailabilityChecker.workdayCXSQuery(for: url))
    }

    /// TASK-613 (job #195): Workday's newer `/details/` deep-link format must parse like `/job/`.
    func testWorkdayCXSQuery_detailsPathFormat_parses() throws {
        let url = try XCTUnwrap(URL(string:
            "https://zillow.wd5.myworkdayjobs.com/en-US/Zillow_Group_External/details/Principal-Product-Technologist_P750648-2"))
        let cxs = try XCTUnwrap(AvailabilityChecker.workdayCXSQuery(for: url))
        XCTAssertEqual(
            cxs.endpoint.absoluteString,
            "https://zillow.wd5.myworkdayjobs.com/wday/cxs/zillow/Zillow_Group_External/jobs"
        )
        XCTAssertEqual(cxs.reqId, "P750648")
    }

    /// TASK-613 (job #195): a removed requisition on a `/details/` URL is now consulted via CXS and
    /// classified gone (previously the `/details/` URL wasn't recognized, so CXS was skipped).
    func testWorkdayDetailsURL_removedRequisition_isGone() async throws {
        let url = "https://zillow.wd5.myworkdayjobs.com/en-US/Zillow_Group_External/details/Principal-PT_P750648-2"
        MockURLProtocol.handlers = [("wday/cxs", { _ in
            makeResponse(url: url, status: 200, body: #"{"total":0,"jobPostings":[]}"#)
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)), title: "Principal Product Technologist", session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone, got \(result)"); return }
        XCTAssertTrue(reason.contains("P750648"), "reason should cite the requisition, got: \(reason)")
    }

    // MARK: LinkedIn search-URL canonicalization (jobs #218/#224)

    /// TASK-613: a `/jobs/search/?currentJobId=N` deep-link is rewritten to the posting view so the
    /// closed banner is visible; other URLs (including an existing `/jobs/view/`) are unchanged.
    func testLinkedInCanonicalJobURL_rewritesSearchToView() throws {
        let search = try XCTUnwrap(URL(string:
            "https://www.linkedin.com/jobs/search/?currentJobId=4442611206&keywords=remote&start=25"))
        XCTAssertEqual(
            AvailabilityChecker.linkedInCanonicalJobURL(search).absoluteString,
            "https://www.linkedin.com/jobs/view/4442611206"
        )
        let view = try XCTUnwrap(URL(string: "https://www.linkedin.com/jobs/view/4442611206"))
        XCTAssertEqual(AvailabilityChecker.linkedInCanonicalJobURL(view), view, "view URLs are untouched")
        let other = try XCTUnwrap(URL(string: "https://example.com/jobs/search/?currentJobId=1"))
        XCTAssertEqual(AvailabilityChecker.linkedInCanonicalJobURL(other), other, "non-LinkedIn is untouched")
    }

    /// TASK-613 (jobs #218/#224): checking a LinkedIn search deep-link for a closed posting reaches the
    /// view page (where the "no longer accepting" banner is served) and classifies it gone.
    func testLinkedInSearchURL_closedPosting_isGone() async throws {
        let search = "https://www.linkedin.com/jobs/search/?currentJobId=4442611206&start=25"
        MockURLProtocol.handlers = [("linkedin.com/jobs/view/4442611206", { _ in
            makeResponse(
                url: "https://www.linkedin.com/jobs/view/4442611206",
                status: 200,
                body: "<h1>Staff Program Manager</h1>we are no longer accepting applications for this role"
            )
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: search)), title: "Staff Program Manager", session: session
        )
        guard case .gone = result else { XCTFail("Expected .gone, got \(result)"); return }
    }

    /// Job #119: a removed Workday requisition still returns a 200 HTML shell, but the CXS API lists
    /// zero matching postings — that absence is the gone signal.
    func testWorkdayRemovedRequisition_notInCXS_isGone() async throws {
        let url = "https://zillow.wd5.myworkdayjobs.com/en-US/Zillow_Group_External/job/Senior-TPM_P750186-2"
        MockURLProtocol.handlers = [("wday/cxs", { _ in
            makeResponse(url: url, status: 200, body: #"{"total":0,"jobPostings":[]}"#)
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)), title: "Senior Technical Program Manager", session: session
        )
        guard case let .gone(reason) = result else { XCTFail("Expected .gone, got \(result)"); return }
        XCTAssertTrue(reason.contains("P750186"), "reason should cite the requisition, got: \(reason)")
    }

    func testWorkdayLiveRequisition_listedInCXS_isAvailable() async throws {
        let url = "https://zillow.wd5.myworkdayjobs.com/en-US/Zillow_Group_External/job/Senior-TPM_P750186-2"
        MockURLProtocol.handlers = [("wday/cxs", { _ in
            makeResponse(
                url: url,
                status: 200,
                body:
                #"{"total":1,"jobPostings":[{"externalPath":"/job/Remote-USA/Senior-TPM_P750186-2","bulletFields":["P750186"]}]}"#
            )
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)), title: "Senior Technical Program Manager", session: session
        )
        guard case .available = result else { XCTFail("Expected .available, got \(result)"); return }
    }

    /// A Workday CXS API failure is indeterminate — never false-expire the job.
    func testWorkdayCXSUnreachable_isAvailable() async throws {
        let url = "https://zillow.wd5.myworkdayjobs.com/en-US/Zillow_Group_External/job/Senior-TPM_P750186-2"
        MockURLProtocol.handlers = [("wday/cxs", { _ in
            makeResponse(url: url, status: 500, body: "error")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)), title: "Senior Technical Program Manager", session: session
        )
        guard case .available = result else { XCTFail("Expected .available, got \(result)"); return }
    }

    // MARK: Cloudflare / bot-challenge (jobs #48, #122)

    // TASK-603: job #122 (a pinterestcareers.com posting behind Cloudflare) was reported as gone
    // because a plain background request gets a 403 "Just a moment…" challenge, not the real page.
    // It's now classified .unverifiable (checkURL step 1.9), so no expired proposal is made while the
    // posting is actually live — the exact response shape this fixture reproduces.
    /// TASK-637: jobright.ai renders jobs client-side; its 200 SPA shell embeds "expired"/"was closed"
    /// job-state templates for every job, so body-gone heuristics must be skipped → unverifiable, not gone.
    func testBodyUnreliableHost_spaShellIsUnverifiableNotGone() async throws {
        let url = "https://jobright.ai/jobs/info/6a53a1f68a74e077472f90e2"
        MockURLProtocol.handlers = [("jobright.ai", { _ in
            // Shell markup that WOULD trip bodyGoneReason on a normal host ("job posting has expired").
            makeResponse(url: url, status: 200,
                         body: "<div id='index_expired-job'>this job posting has expired, was closed</div>")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)), title: "Staff PM", session: session
        )
        guard case let .unverifiable(reason) = result else {
            XCTFail("Expected .unverifiable for jobright.ai SPA shell, got \(result)"); return
        }
        XCTAssertTrue(reason.contains("client-rendered shell"), "reason: \(reason)")
    }

    /// A hard 404 on a body-unreliable host is still authoritatively gone (status codes precede the skip).
    func testBodyUnreliableHost_real404IsStillGone() async throws {
        let url = "https://jobright.ai/jobs/info/deadbeef"
        MockURLProtocol.handlers = [("jobright.ai", { _ in makeResponse(url: url, status: 404, body: "") })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)), title: "Staff PM", session: session
        )
        guard case .gone = result else { XCTFail("Expected .gone for a real 404, got \(result)"); return }
    }

    func testIsBodyUnreliableHost_matchesHostAndSubdomains() {
        XCTAssertTrue(AvailabilityChecker.isBodyUnreliableHost("https://jobright.ai/jobs/info/x"))
        XCTAssertTrue(AvailabilityChecker.isBodyUnreliableHost("https://www.jobright.ai/x"))
        XCTAssertTrue(AvailabilityChecker.isBodyUnreliableHost("https://app.jobright.ai/x"))
        XCTAssertFalse(AvailabilityChecker.isBodyUnreliableHost("https://greenhouse.io/x"))
    }

    func testCloudflareChallenge_403_isUnverifiable() async throws {
        let url = "https://www.pinterestcareers.com/jobs/7562128/technical-program-manager-ii-platforms/"
        MockURLProtocol.handlers = [("pinterestcareers.com/jobs/7562128", { _ in
            makeResponse(url: url, status: 403, body: "<title>Just a moment...</title>")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: url)), title: "Technical Program Manager II Platforms", session: session
        )
        guard case let .unverifiable(reason) = result else {
            XCTFail("Expected .unverifiable, got \(result)"); return
        }
        XCTAssertTrue(reason.contains("bot challenge"), "reason: \(reason)")
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

    func testLinkedIn404IsGone() async throws {
        // TASK-639 (job #212): a LinkedIn guest `/jobs/view/{id}` 404 is a reliable removed-posting
        // signal with the app's browser UA (verified vs LinkedIn's guest job API), so it must be gone —
        // the earlier "unverifiable" carve-out suppressed real removals.
        let originalURL = "https://www.linkedin.com/jobs/view/999"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: originalURL, status: 404, body: "")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Whatever Role Here",
            session: session
        )
        guard case .gone = result else { XCTFail("Expected .gone for a LinkedIn 404, got \(result)"); return }
    }

    func testNonLinkedIn404IsStillGone() async throws {
        let originalURL = "https://boards.greenhouse.io/acme/jobs/999"
        MockURLProtocol.handlers = [(originalURL, { _ in
            makeResponse(url: originalURL, status: 404, body: "")
        })]
        let result = try await AvailabilityChecker.checkURL(
            XCTUnwrap(URL(string: originalURL)),
            title: "Whatever Role Here",
            session: session
        )
        guard case .gone = result else { XCTFail("Expected .gone for non-LinkedIn 404, got \(result)"); return }
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

    // MARK: - TASK-631: Greenhouse authoritative confirm-alive override

    /// The career-site HTML looks gone (Cloudflare/JS-shell), but the Greenhouse Job Board API returns
    /// 200 for the gh_jid — the job is authoritatively live, so it must NOT surface as a gone candidate.
    func testFindGoneJobs_greenhouse200OverridesGoneHTML() async throws {
        let career = "https://www.pinterestcareers.com/jobs/7494634/staff-tpm/?gh_jid=7494634"
        let job = try makeJobWithCapture(url: career, title: "Staff TPM", status: .applied)
        job.company = "Pinterest"
        MockURLProtocol.handlers = [
            ("pinterestcareers.com", { _ in makeResponse(url: career, status: 200, body: "this job is no longer available") }),
            ("boards-api.greenhouse.io/v1/boards/pinterest/jobs/7494634", { _ in
                makeResponse(url: "https://boards-api.greenhouse.io/v1/boards/pinterest/jobs/7494634",
                             status: 200, body: "{\"id\":7494634}")
            })
        ]
        let gone = await AvailabilityChecker.findGoneJobs([job], session: session)
        XCTAssertTrue(gone.isEmpty, "Greenhouse 200 must override the gone-looking career HTML")
    }

    /// When Greenhouse does NOT confirm alive (404 / wrong board), the gone HTML result stands — a
    /// genuinely dead posting is still caught (no new false negatives).
    func testFindGoneJobs_greenhouseNon200FallsThroughToGone() async throws {
        let career = "https://www.pinterestcareers.com/jobs/7494634/staff-tpm/?gh_jid=7494634"
        let job = try makeJobWithCapture(url: career, title: "Staff TPM", status: .applied)
        job.company = "Pinterest"
        MockURLProtocol.handlers = [
            ("pinterestcareers.com", { _ in makeResponse(url: career, status: 200, body: "this job is no longer available") }),
            // Any boards-api request 404s (must be explicit — the mock defaults unmatched URLs to 200).
            ("boards-api.greenhouse.io", { _ in
                makeResponse(url: "https://boards-api.greenhouse.io/x", status: 404, body: "{}")
            })
        ]
        let gone = await AvailabilityChecker.findGoneJobs([job], session: session)
        XCTAssertEqual(gone.count, 1, "Greenhouse 404 must fall through to the gone HTML result")
    }

    func testGreenhouseJobID_extractsGhJidFromAnyURL() {
        XCTAssertEqual(
            AvailabilityChecker.greenhouseJobID(fromURLs: [
                nil, "https://x.com/no-id", "https://www.pinterestcareers.com/jobs/?gh_jid=7494634"
            ]),
            "7494634"
        )
        XCTAssertNil(AvailabilityChecker.greenhouseJobID(fromURLs: ["https://example.com/careers/role"]))
    }

    /// TASK-642: a LinkedIn search URL (currentJobId) is checked via the guest job API in the paced pass;
    /// a 404 there = removed → gone.
    func testFindGoneJobs_linkedInGuestAPI404IsGone() async throws {
        let search = "https://www.linkedin.com/jobs/search/?currentJobId=999&keywords=remote"
        let job = try makeJobWithCapture(url: search, title: "Role", status: .applied)
        MockURLProtocol.handlers = [("jobs-guest/jobs/api/jobPosting/999", { _ in
            makeResponse(url: "https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/999", status: 404, body: "")
        })]
        let gone = await AvailabilityChecker.findGoneJobs([job], session: session)
        XCTAssertEqual(gone.count, 1, "a removed LinkedIn posting (guest API 404) is caught")
        XCTAssertEqual(gone.first?.jobID, job.id)
    }

    /// A LinkedIn guest-API 200 whose body carries the closed banner is gone; a live 200 is not.
    func testFindGoneJobs_linkedInGuestAPI200ClosedVsLive() async throws {
        let closedURL = "https://www.linkedin.com/jobs/search/?currentJobId=111"
        let liveURL = "https://www.linkedin.com/jobs/search/?currentJobId=222"
        let closed = try makeJobWithCapture(url: closedURL, title: "Closed", status: .applied)
        _ = try makeJobWithCapture(url: liveURL, title: "Live", status: .applied)
        MockURLProtocol.handlers = [
            ("jobs-guest/jobs/api/jobPosting/111", { _ in
                makeResponse(url: "https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/111",
                             status: 200, body: "<figure class=\"closed-job__flavor\">no longer accepting applications</figure>")
            }),
            ("jobs-guest/jobs/api/jobPosting/222", { _ in
                makeResponse(url: "https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/222",
                             status: 200, body: "<button>Apply</button> Actively recruiting")
            })
        ]
        let gone = await AvailabilityChecker.findGoneJobs([closed], session: session)
        XCTAssertEqual(gone.count, 1, "closed LinkedIn posting is gone")
        XCTAssertEqual(gone.first?.jobID, closed.id)
    }

    func testLinkedInJobID_extractsFromSearchAndViewURLs() throws {
        let search = try XCTUnwrap(URL(string: "https://www.linkedin.com/jobs/search/?currentJobId=4442490941&keywords=x"))
        let view = try XCTUnwrap(URL(string: "https://www.linkedin.com/jobs/view/4443545630/"))
        let noID = try XCTUnwrap(URL(string: "https://www.linkedin.com/jobs/search/?keywords=x"))
        XCTAssertEqual(AvailabilityChecker.linkedInJobID(from: search), "4442490941")
        XCTAssertEqual(AvailabilityChecker.linkedInJobID(from: view), "4443545630")
        XCTAssertNil(AvailabilityChecker.linkedInJobID(from: noID))
    }

    func testGreenhouseBoardCandidates_derivation() {
        XCTAssertEqual(
            AvailabilityChecker.greenhouseBoardCandidates(
                company: "Pinterest", urlString: "https://www.pinterestcareers.com/jobs/7494634/?gh_jid=7494634"
            ),
            ["pinterest", "pinterestcareers"], "strip 'careers' suffix; company slug dedups"
        )
        XCTAssertEqual(
            AvailabilityChecker.greenhouseBoardCandidates(
                company: "Reddit", urlString: "https://job-boards.greenhouse.io/reddit/jobs/123"
            ),
            ["reddit"], "greenhouse.io host → board is authoritative in the path"
        )
    }

    /// TASK-608: with no cap, every eligible stale job is returned so a large backlog drains in one
    /// pass; an explicit cap still bounds the result.
    func testFetchStaleEligibleJobs_uncappedReturnsAllStale() async throws {
        let staleDate = Date().addingTimeInterval(-30 * 86400)
        for i in 0 ..< 40 {
            _ = try makeJobWithCapture(
                url: "https://stale.example.com/job/\(i)",
                title: "Stale \(i)",
                status: .pursuing,
                capturedAt: staleDate.addingTimeInterval(-Double(i) * 3600)
            )
        }

        let uncapped = try await AvailabilityChecker.fetchStaleEligibleJobs(store: store, staleDays: 21, limit: nil)
        XCTAssertEqual(uncapped.count, 40, "no cap must return all 40 eligible stale jobs (was capped at 25)")

        let capped = try await AvailabilityChecker.fetchStaleEligibleJobs(store: store, staleDays: 21, limit: 5)
        XCTAssertEqual(capped.count, 5, "an explicit cap still bounds the result")
    }

    /// TASK-621: actively-pursued jobs are re-checked every run regardless of the staleness window,
    /// while other statuses still wait for it — so fast-expiring pursued jobs aren't missed for weeks.
    func testFetchStaleEligibleJobs_alwaysChecksPursuedRegardlessOfAge() async throws {
        let fresh = Date() // well within the 21-day window
        _ = try makeJobWithCapture(url: "https://x.com/pursuing", title: "P", status: .pursuing, capturedAt: fresh)
        _ = try makeJobWithCapture(url: "https://x.com/applied", title: "A", status: .applied, capturedAt: fresh)
        _ = try makeJobWithCapture(url: "https://x.com/new", title: "N", status: .new, capturedAt: fresh)

        // Without always-check, none are stale → none eligible.
        let staleOnly = try await AvailabilityChecker.fetchStaleEligibleJobs(store: store, staleDays: 21, limit: nil)
        XCTAssertTrue(staleOnly.isEmpty, "fresh jobs aren't stale")

        // With always-check for pursued statuses, the pursuing + applied jobs are eligible; new is not.
        let withPursued = try await AvailabilityChecker.fetchStaleEligibleJobs(
            store: store, staleDays: 21, limit: nil, alwaysCheckStatuses: ["pursuing", "applied"]
        )
        XCTAssertEqual(withPursued.count, 2, "pursuing + applied are always checked; new still waits for staleness")
        XCTAssertTrue(withPursued.allSatisfy { $0.status == .pursuing || $0.status == .applied })
    }

    /// TASK-626: a job the user resolved as a duplicate must NOT be availability-checked — expiring a
    /// duplicate is wasted work (the user tracks the original). `.duplicate` is a terminal status.
    func testFetchStaleEligibleJobs_excludesDuplicates() async throws {
        let staleDate = Date().addingTimeInterval(-30 * 86400)
        _ = try makeJobWithCapture(url: "https://x.com/live", title: "Live", status: .pursuing, capturedAt: staleDate)
        _ = try makeJobWithCapture(url: "https://x.com/dup", title: "Dup", status: .duplicate, capturedAt: staleDate)

        let eligible = try await AvailabilityChecker.fetchStaleEligibleJobs(store: store, staleDays: 21, limit: nil)
        XCTAssertEqual(eligible.count, 1, "the duplicate must be excluded; only the live pursuing job is eligible")
        XCTAssertTrue(eligible.allSatisfy { $0.status != .duplicate })
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

    // MARK: - maybeFindStaleGoneJobs (confirm-first background pass)

    func testMaybeFindStaleGoneJobs_returnsAppliedCandidate_withoutExpiring() async throws {
        MockURLProtocol.handlers = [("gone.example.com", { _ in
            makeResponse(url: "https://gone.example.com/job/9", status: 404, body: "not found")
        })]
        let old = Date().addingTimeInterval(-60 * 86400)
        _ = try makeJobWithCapture(
            url: "https://gone.example.com/job/9", title: "Applied Gone Job",
            status: .applied, capturedAt: old
        )
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        settings.setBool(true, forKey: SettingsKey.availabilityAutoCheckEnabled)
        settings.set("2020-01-01T00:00:00Z", forKey: SettingsKey.availabilityLastAutoCheckAt)
        settings.set("21", forKey: SettingsKey.availabilityStaleDays)

        let found = await AvailabilityChecker.maybeFindStaleGoneJobs(
            store: store, settings: settings, session: session
        )
        XCTAssertEqual(found?.count, 1, "an Applied job that 404s must be returned as a candidate")
        XCTAssertEqual(found?.first?.title, "Applied Gone Job")

        // Confirm-first: the candidate must NOT be auto-expired.
        let refetched = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(refetched.first?.status, .applied, "candidate must not be auto-expired")
    }

    func testMaybeFindStaleGoneJobs_skipsWhenDisabled() async {
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        settings.setBool(false, forKey: SettingsKey.availabilityAutoCheckEnabled)
        let found = await AvailabilityChecker.maybeFindStaleGoneJobs(
            store: store, settings: settings, session: session
        )
        XCTAssertNil(found, "disabled auto-check must return nil (skipped)")
    }
}

// swiftlint:enable force_unwrapping
