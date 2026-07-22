// swiftlint:disable line_length large_tuple
import Foundation
import SwiftData

// MARK: - Result type

public enum URLAvailabilityResult: Sendable {
    case available
    case gone(reason: String)
    /// The posting could not be verified either way — e.g. the request hit a bot-challenge / login
    /// wall that never serves the real page (job #48). Distinct from `.available` so callers can
    /// surface "couldn't check" instead of implying the job is still live, and distinct from `.gone`
    /// so it never triggers an expiry.
    case unverifiable(reason: String)
    case error(Error)
}

// MARK: - Domain events

public extension Notification.Name {
    static let jobUnavailable = Notification.Name("jobhunt.jobUnavailable")
    /// Posted by the confirm-first background pass when one or more jobs look gone and the user should
    /// be prompted to review them (userInfo: `count`). No status has been changed — the app surfaces a
    /// notification and opens the confirmation UI. See `AvailabilityChecker.maybeFindStaleGoneJobs`.
    static let jobsMaybeUnavailable = Notification.Name("jobhunt.jobsMaybeUnavailable")
}

/// userInfo keys for the `jobsMaybeUnavailable` notification.
public enum JobsMaybeUnavailableKey {
    public static let count = "count"
}

/// Keys for jobUnavailable notification userInfo.
public enum JobUnavailableKey {
    public static let jobID = "jobID"
    public static let jobNumber = "jobNumber"
    public static let title = "title"
    public static let reason = "reason"
}

// MARK: - GoneJobResult

/// A job found to be unavailable during a check. Returned to the caller for user confirmation
/// before any status change is made.
public struct GoneJobResult: Sendable {
    public let jobID: String
    public let jobNumber: Int?
    public let company: String?
    public let title: String
    public let url: URL
    public let reason: String
}

// MARK: - AvailabilityChecker

/// Ports server/availability.js: URL liveness detection + stale-job scheduler.
public enum AvailabilityChecker {
    // MARK: - Constants (mirroring JS)

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    static let goneStatusCodes: Set<Int> = [404, 410]
    /// Heuristic removal-phrase lists — expect to keep extending these as new sites/wording surface.
    /// Add literal phrases here and generalized families to `goneBodyRegexes` below (see docs/tuning.md).
    static let goneBodyPatterns: [String] = [
        "page not found", "job not found", "job no longer available",
        "this job is no longer", "position is no longer available", "position has been filled",
        "posting has expired", "job posting has expired", "no longer accepting applications",
        "job listing has expired", "this position has been filled", "this role is no longer",
        "opening is no longer", "requisition is no longer", "job has been closed",
        "this job has been removed"
    ]
    /// Generalized "posting is gone" families, matched (ICU regex) against the lowercased body.
    /// These complement the literal `goneBodyPatterns` above so a new site with slightly different
    /// wording is still caught without adding a literal for each — e.g. Built In keeps a removed
    /// posting at HTTP 200 with the title still on the page and only an inline "Sorry, this job was
    /// removed at …" banner, which the status/redirect/title heuristics all miss. Anchored to a
    /// job-subject noun (job/position/posting/role/listing/opening/requisition/vacancy) so unrelated
    /// "no longer"/"removed" copy elsewhere on the page doesn't false-positive. Expect to keep
    /// tuning these as new phrasings surface.
    static let goneBodyRegexes: [String] = [
        // … <subject> was|is|has (been)|… removed|closed|filled|taken down|deactivated|…
        #"\b(job|position|posting|role|listing|opening|requisition|vacancy)\s+(has been|have been|was|were|is|are|has|have)\s+(removed|closed|filled|taken down|deactivated|cancelled|canceled|deleted|withdrawn)\b"#,
        // … <subject> (is|are|has|…) no longer available|open|active|posted|accepting|live
        #"\b(job|position|posting|role|listing|opening|requisition|vacancy)\s+(?:is|are|was|were|has|have)?\s*no longer\s+(available|open|active|posted|accepting|live)\b"#,
        // "no longer accepting applications" — common enough to match without a subject noun
        #"\bno longer accepting applications\b"#,
        // … <subject> (posting) (has) expired
        #"\b(job|position|posting|listing|role|opening|requisition)\s+(?:posting\s+)?(?:has\s+|have\s+)?expired\b"#,
        // "<subject> not found"
        #"\b(job|position|posting|page|listing)\s+not\s+found\b"#
    ]
    /// 30s (was a legacy 12s): slow-but-alive ATS pages (Workday etc.) were timing out and counting as
    /// a failed check, so the job never got re-verified until the next interval. A timeout still resolves
    /// to `.available` (never `.gone`), so a longer wait only costs latency on genuinely slow hosts.
    static let timeoutSeconds: TimeInterval = 30

    // MARK: - URL normalization helpers

    /// Strips fragment, sorts query params, removes trailing slash from path.
    /// Returns nil if the URL has no scheme or host (i.e. is not an absolute HTTP URL).
    static func normalizedURL(_ rawURL: String) -> URL? {
        guard var components = URLComponents(string: rawURL),
              let scheme = components.scheme, !scheme.isEmpty,
              let host = components.host, !host.isEmpty else { return nil }
        components.fragment = nil
        if let items = components.queryItems {
            components.queryItems = items.sorted { $0.name < $1.name }
        }
        var path = components.path
        while path.hasSuffix("/") && path.count > 1 {
            path = String(path.dropLast())
        }
        if path.isEmpty { path = "/" }
        components.path = path
        return components.url
    }

    /// Returns a "gone" reason if the page body carries a removal/closure signal, else nil.
    /// Checks the literal `goneBodyPatterns` first (fast, explicit), then the generalized
    /// `goneBodyRegexes` families. `body` MUST already be lowercased. The reason cites the actual
    /// matched text so logs/audit events show exactly what tripped the check.
    static func bodyGoneReason(_ body: String) -> String? {
        for pattern in goneBodyPatterns where body.contains(pattern) {
            return "body: \(pattern)"
        }
        for pattern in goneBodyRegexes {
            if let range = body.range(of: pattern, options: .regularExpression) {
                return "body: \(body[range])"
            }
        }
        return nil
    }

    /// True when `title` has ≥3 meaningful words (mirrors isMeaningfulTitle).
    static func isMeaningfulTitle(_ title: String) -> Bool {
        normalizedText(title).split(separator: " ").count(where: { !$0.isEmpty }) >= 3
    }

    static func normalizedText(_ value: String) -> String {
        let lower = value.lowercased()
        let cleaned = lower.unicodeScalars.map { scalar -> Character in
            let codePoint = scalar.value
            if (codePoint >= 97 && codePoint <= 122) ||
                (codePoint >= 48 && codePoint <= 57) { return Character(scalar) } // a-z, 0-9
            return " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// True when body contains the normalized title (mirrors bodyContainsTitle — skips short titles).
    static func bodyContainsTitle(_ body: String, title: String) -> Bool {
        guard isMeaningfulTitle(title) else { return true }
        return normalizedText(body).contains(normalizedText(title))
    }

    /// True when a redirect went from a job URL to a non-job page on the same domain.
    /// Cross-domain redirects return false (not classified as gone by this heuristic).
    static func redirectedToNonJobPage(originalURLString: String, finalURLString: String) -> Bool {
        guard let orig = normalizedURL(originalURLString),
              let final = normalizedURL(finalURLString) else { return false }
        // If URLs are effectively identical, no redirect.
        if orig.absoluteString == final.absoluteString { return false }

        guard let origComponents = URLComponents(url: orig, resolvingAgainstBaseURL: false),
              let finalComponents = URLComponents(url: final, resolvingAgainstBaseURL: false) else {
            return false
        }

        // Cross-domain redirects: not classified as non-job by this heuristic.
        guard origComponents.host == finalComponents.host else { return false }

        let path = (finalComponents.path.lowercased() as NSString).standardizingPath
        let trimmedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        let origPath = (origComponents.path.lowercased() as NSString).standardizingPath

        // Redirected to root or generic jobs/careers root.
        if trimmedPath == "" || trimmedPath == "/" || trimmedPath == "/jobs" || trimmedPath == "/careers" {
            return true
        }
        // Redirected to a company page.
        if trimmedPath.contains("/company/") || trimmedPath.contains("/companies/") {
            return true
        }
        // Redirected to a search/listings page (different path ending in /search, /jobs, /careers, /openings).
        if trimmedPath != origPath {
            let suffixes = ["/search", "/jobs", "/careers", "/openings"]
            if suffixes.contains(where: { trimmedPath.hasSuffix($0) }) {
                return true
            }
        }
        return false
    }

    /// Upgrade an `http://` URL to `https://` for the availability request. Job boards are
    /// universally HTTPS and 301-redirect http→https anyway, but macOS App Transport Security blocks
    /// the initial plain-HTTP request outright (URLSession throws `-1022` before any redirect is
    /// followed), so an http-only job URL would otherwise never be fetched and never be flagged gone —
    /// the check would silently resolve to "available" every time (TASK-594). Non-http(s) or
    /// already-secure URLs are returned unchanged.
    static func httpsUpgraded(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "http" else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    /// True when the final URL is a known applicant-tracking board's "posting not found" landing page.
    /// Some ATSes keep a removed posting at HTTP 200 by redirecting to a board-level error page, so the
    /// status-code, body-phrase, and redirect-suffix heuristics all miss it. Each rule is scoped to a
    /// specific ATS host and a marker a *live* posting URL never carries, so none can false-positive on
    /// an available job. Add a new ATS here as its "gone" landing is confirmed (TASK-594).
    ///   • Greenhouse — 302 → `…/{board}?error=true` (job #37).
    ///   • Workable   — 302 → `…/oops` for a removed/unknown posting.
    /// Boards that instead return a real 404/410 (Lever, SmartRecruiters) are already handled by the
    /// status-code check and need no rule here. Fully client-rendered boards (e.g. Ashby) serve a
    /// generic HTML shell at 200 with no server-side gone signal and can't be classified this way.
    static func isBoardErrorLandingURL(_ urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString) else { return false }
        let host = (components.host ?? "").lowercased()
        let path = components.path.lowercased()
        // Greenhouse: `?error=true` on the board root.
        if host.contains("greenhouse.io"),
           components.queryItems?.contains(where: { $0.name == "error" && $0.value == "true" }) ?? false {
            return true
        }
        // Workable: redirect to the `/oops` error landing.
        if host.contains("workable.com"), path == "/oops" {
            return true
        }
        return false
    }

    /// True when a LinkedIn public guest job page carries the structured "closed job" banner LinkedIn
    /// renders for a posting no longer accepting applications
    /// (`<figure class="closed-job …"><figcaption class="closed-job__flavor--closed">…`). The visible
    /// English text ("No longer accepting applications") is already matched by `bodyGoneReason`; this
    /// markup class is a wording/locale-independent backstop, scoped to LinkedIn hosts so the generic
    /// class name can't false-positive elsewhere. `body` MUST already be lowercased. NOTE: LinkedIn
    /// sometimes redirects an un-authenticated check to an auth wall instead of the guest view (see
    /// `isAuthWallURL`); when it does, this marker is absent and the job is left available, not gone.
    static func isLinkedInClosedJob(finalURLString: String, body: String) -> Bool {
        guard let host = URLComponents(string: finalURLString)?.host?.lowercased(),
              host.contains("linkedin.com") else { return false }
        return body.contains("closed-job__flavor")
    }

    /// True when the response is a Cloudflare / bot-challenge interstitial rather than the real page.
    /// Career sites on Phenom (e.g. `pinterestcareers.com`, job #48) sit behind Cloudflare, which
    /// serves a "Just a moment…" challenge (HTTP 403) to a plain background request — the actual
    /// posting is never delivered, so its availability is genuinely indeterminate. `body` MUST already
    /// be lowercased. Scoped to the challenge markers so an ordinary 403 without a challenge falls
    /// through to the normal heuristics.
    static func isBotChallenge(_ body: String) -> Bool {
        if body.contains("just a moment") { return true }
        if body.contains("challenge-platform") || body.contains("cf-mitigated") ||
            body.contains("_cf_chl_opt") || body.contains("cf-challenge") { return true }
        if body.contains("attention required") && body.contains("cloudflare") { return true }
        return false
    }

    /// LinkedIn `…/jobs/search/?currentJobId=N` and `…/jobs/collections/…?currentJobId=N` URLs point at
    /// a results page that merely highlights a job — the posting's "No longer accepting applications" /
    /// closed banner is NOT in that page's server response, so a removed posting reads as available
    /// (jobs #218/#224). Rewrite such URLs to the public posting view `…/jobs/view/N`, where the closed
    /// banner IS served and the existing detection (`bodyGoneReason`, `isLinkedInClosedJob`) can see it.
    /// Any non-matching URL (including an existing `/jobs/view/` URL) is returned unchanged.
    static func linkedInCanonicalJobURL(_ url: URL) -> URL {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased(), host.hasSuffix("linkedin.com"),
              comps.path.contains("/jobs/"), !comps.path.contains("/jobs/view/"),
              let jobID = comps.queryItems?.first(where: { $0.name == "currentJobId" })?.value,
              !jobID.isEmpty, jobID.allSatisfy(\.isNumber),
              let viewURL = URL(string: "https://www.linkedin.com/jobs/view/\(jobID)") else {
            return url
        }
        return viewURL
    }

    // MARK: - Workday CXS availability

    /// Workday postings are fully client-rendered: the HTML job URL returns a generic 200 shell
    /// whether or not the requisition still exists, so the status/body/redirect heuristics can never
    /// see a removed Workday job (job #119). Workday does expose a public JSON API (CXS) that lists a
    /// tenant's live requisitions, so for a `*.myworkdayjobs.com` URL we query that by requisition id
    /// instead. Returns the CXS search endpoint + the requisition id, or nil if the URL isn't a
    /// parseable Workday job URL.
    ///
    /// A Workday job path is `/[locale/]{site}/job/{slug}_{reqId}[-postingIndex]`, e.g.
    /// `…/en-US/Zillow_Group_External/job/…_P750186-2`; the CXS endpoint is
    /// `https://{host}/wday/cxs/{tenant}/{site}/jobs` and the requisition id is `P750186`.
    static func workdayCXSQuery(for url: URL) -> (endpoint: URL, reqId: String)? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased(), host.hasSuffix("myworkdayjobs.com"),
              let tenant = host.split(separator: ".").first.map(String.init), !tenant.isEmpty else {
            return nil
        }
        // The site is the path segment immediately before the job marker. Workday deep-links come in
        // two shapes — `/[locale/]{site}/job/{slug}_{reqId}` and the newer share/detail format
        // `/[locale/]{site}/details/{slug}_{reqId}` (job #195) — so accept either "job" or "details".
        let segments = comps.path.split(separator: "/").map(String.init)
        guard let markerIdx = segments.firstIndex(where: { $0 == "job" || $0 == "details" }),
              markerIdx >= 1, markerIdx + 1 < segments.count else {
            return nil
        }
        let site = segments[markerIdx - 1]
        // Requisition id: trailing `_P123456` token of the final segment, minus any `-N` posting index.
        guard let last = segments.last, let underscore = last.lastIndex(of: "_") else { return nil }
        var reqId = String(last[last.index(after: underscore)...])
        if let dash = reqId.range(of: #"-\d+$"#, options: .regularExpression) {
            reqId.removeSubrange(dash)
        }
        guard !reqId.isEmpty,
              let endpoint = URL(string: "https://\(host)/wday/cxs/\(tenant)/\(site)/jobs") else {
            return nil
        }
        return (endpoint, reqId)
    }

    /// Queries the Workday CXS API for a requisition id. Returns `true` if a live posting matching the
    /// id is listed, `false` if the tenant returns no matching posting (job removed), or `nil` if the
    /// API can't be reached / the response is unparseable — nil is treated as indeterminate (not gone)
    /// so a transient API failure never false-expires a job.
    static func workdayReqStillListed(endpoint: URL, reqId: String, session: URLSession) async -> Bool? {
        var request = URLRequest(url: endpoint, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["limit": 20, "offset": 0, "searchText": reqId]
        )
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let postings = (json["jobPostings"] as? [[String: Any]]) ?? []
        let idLower = reqId.lowercased()
        return postings.contains { posting in
            if let bullets = posting["bulletFields"] as? [String],
               bullets.contains(where: { $0.lowercased() == idLower }) { return true }
            if let path = posting["externalPath"] as? String, path.lowercased().contains(idLower) {
                return true
            }
            return false
        }
        // Exact-id match required: `searchText` on a requisition id is precise, so no match (empty or
        // only unrelated fuzzy results) means the requisition is gone.
    }

    /// True when a URL is a login / auth wall or an aggregator's "can't show this posting without
    /// login" fallback. Some sites (notably LinkedIn) redirect an un-authenticated availability
    /// check to such a page instead of the posting — that is NOT evidence the job is gone, so the
    /// redirect heuristics must be skipped to avoid false-positive expirations.
    static func isAuthWallURL(_ urlString: String) -> Bool {
        guard let comps = URLComponents(string: urlString) else { return false }
        let host = (comps.host ?? "").lowercased()
        let path = comps.path.lowercased()
        // Generic login / auth-wall paths (applies to any site).
        let authFragments = [
            "/login", "/signin", "/sign-in", "/authwall", "/uas/login",
            "/checkpoint", "/account/login", "/sso/", "/auth/realms"
        ]
        if authFragments.contains(where: { path.contains($0) }) { return true }
        // LinkedIn serves a generic "collections / similar jobs" page when a specific posting
        // can't be viewed without login — ambiguous, so treat it as indeterminate, not gone.
        if host.contains("linkedin.com"),
           path.contains("/jobs/collections") || path.contains("/jobs/search") {
            return true
        }
        return false
    }

    // MARK: - checkURL

    /// Checks whether a single job URL is still live. Mirrors checkUrl() in availability.js.
    /// - Parameters:
    ///   - url: The job posting URL.
    ///   - title: The job title (used for redirect/title heuristics).
    ///   - session: URLSession to use (injectable for testing).
    /// - Returns: `.available`, `.gone(reason:)`, or `.error(_)`.
    public static func checkURL(
        _ url: URL,
        title: String,
        session: URLSession = .shared
    ) async -> URLAvailabilityResult {
        // ATS blocks plain-HTTP external requests, so upgrade http→https for the request (and use the
        // upgraded URL as the redirect-comparison baseline, so the upgrade isn't itself counted as a
        // redirect). TASK-594. Then canonicalize a LinkedIn search/collections deep-link to the posting
        // view so a removed posting's closed banner is actually in the fetched response (job #218/#224).
        let requestURL = linkedInCanonicalJobURL(httpsUpgraded(url))

        // Workday: the HTML is a client-rendered 200 shell whether or not the job exists, so the
        // body/redirect heuristics below can't see a removed requisition. Consult the CXS JSON API by
        // requisition id instead (job #119). API unreachable/ambiguous → available (never false-expire).
        if let cxs = workdayCXSQuery(for: requestURL) {
            switch await workdayReqStillListed(endpoint: cxs.endpoint, reqId: cxs.reqId, session: session) {
            case .some(false): return .gone(reason: "workday requisition \(cxs.reqId) no longer listed")
            case .some(true), .none: return .available
            }
        }

        var request = URLRequest(url: requestURL, timeoutInterval: timeoutSeconds)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .available
            }
            let finalURLString = http.url?.absoluteString ?? requestURL.absoluteString
            let statusCode = http.statusCode

            // 1. Gone status codes.
            if goneStatusCodes.contains(statusCode) {
                return .gone(reason: "HTTP \(statusCode)")
            }

            // 1.5 Applicant-tracking board "posting not found" landing (e.g. Greenhouse redirects a
            // removed posting to `…/{board}?error=true` at HTTP 200). Deterministic gone signal.
            if isBoardErrorLandingURL(finalURLString) {
                return .gone(reason: "board posting not found: \(finalURLString)")
            }

            // 2. Body pattern matching (literal phrases + generalized regex families).
            let body = String(data: data, encoding: .utf8)?.lowercased() ?? ""

            // 1.9 Cloudflare / bot-challenge interstitial (e.g. Phenom-hosted sites like Pinterest,
            // job #48): the real page is never served, so availability is indeterminate — surface it
            // as unverifiable rather than silently "available".
            if statusCode == 403, isBotChallenge(body) {
                return .unverifiable(reason: "bot challenge: \(finalURLString)")
            }

            if let reason = bodyGoneReason(body) {
                return .gone(reason: reason)
            }

            // 2.2 LinkedIn structured "closed job" banner (public guest view, HTTP 200, no redirect).
            // The visible phrase is already covered above; the markup class is a locale-independent
            // backstop for a closed posting whose banner text isn't English (job #130).
            if isLinkedInClosedJob(finalURLString: finalURLString, body: body) {
                return .gone(reason: "linkedin closed-job banner: \(finalURLString)")
            }

            // 2.5 Login / auth wall (e.g. LinkedIn redirecting an un-authenticated check to a
            // collections or login page). We can't determine availability behind a login, so don't
            // flag as gone — the redirect heuristics below would otherwise false-positive.
            if isAuthWallURL(finalURLString) {
                return .available
            }

            // 3. Redirect to non-job page.
            if redirectedToNonJobPage(originalURLString: requestURL.absoluteString, finalURLString: finalURLString) {
                return .gone(reason: "redirected to non-job page: \(finalURLString)")
            }

            // 4. Redirect with missing title.
            let origNorm = normalizedURL(requestURL.absoluteString)?.absoluteString ?? requestURL.absoluteString
            let finalNorm = normalizedURL(finalURLString)?.absoluteString ?? finalURLString
            if origNorm != finalNorm && !bodyContainsTitle(body, title: title) {
                return .gone(reason: "redirected page missing title: \(finalURLString)")
            }

            return .available
        } catch let error as URLError where error.code == .timedOut || error.code == .cancelled {
            // Timeout treated as available (mirrors AbortError → available/timeout in JS).
            return .available
        } catch {
            // Network errors treated as available (mirrors non-AbortError → available/error in JS).
            return .error(error)
        }
    }

    // MARK: - findGoneJobs

    /// Checks the URLs of pursuing jobs and returns those that appear to be gone,
    /// WITHOUT modifying any job records. Call this to gather candidates, then show
    /// a confirmation UI before marking them expired.
    public static func findGoneJobs(
        _ jobs: [Job],
        session: URLSession = .shared
    ) async -> [GoneJobResult] {
        // Interested (.pursuing) AND Applied jobs are checked: a role you applied to can be pulled
        // just as a saved one can. Interview/offer/rejected stay protected — a job you're actively
        // interviewing for belongs in .interview, not .applied. No status is changed here; results are
        // returned for user confirmation.
        let eligible = jobs.filter { $0.status == .pursuing || $0.status == .applied }
        guard !eligible.isEmpty else { return [] }

        struct JobSpec: Sendable {
            let id: String; let jobNumber: Int?; let company: String?; let title: String; let url: URL
        }
        let specs: [JobSpec] = eligible.compactMap { job in
            let urlString = JobURLPolicy.availabilityCheckURL(job: job) ?? ""
            guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
            return JobSpec(id: job.id, jobNumber: job.jobNumber, company: job.company, title: job.title ?? "", url: url)
        }
        guard !specs.isEmpty else { return [] }

        var results: [GoneJobResult] = []
        await withTaskGroup(of: GoneJobResult?.self) { group in
            var inFlight = 0
            for spec in specs {
                if inFlight >= 10 {
                    if let r = await group.next() {
                        if let r { results.append(r) }
                        inFlight -= 1
                    }
                }
                let (id, jobNumber, company, title, url) = (spec.id, spec.jobNumber, spec.company, spec.title, spec.url)
                inFlight += 1
                group.addTask {
                    let result = await checkURL(url, title: title, session: session)
                    if case let .gone(reason) = result {
                        return GoneJobResult(
                            jobID: id, jobNumber: jobNumber, company: company,
                            title: title, url: url, reason: reason
                        )
                    }
                    return nil
                }
            }
            for await r in group {
                if let r { results.append(r) }
            }
        }
        return results
    }

    // MARK: - checkJobs

    /// Lightweight value type for communicating check results across async boundaries.
    private struct CheckedJob {
        let jobID: String
        let jobNumber: Int?
        let title: String
        let url: URL
        let result: URLAvailabilityResult
    }

    /// Checks actively-pursued jobs in parallel (max 10 concurrent).
    /// Auto-expiry is restricted to pursuing jobs only — applied/interview/offer/rejected/duplicate
    /// jobs are protected from automatic status changes.
    /// Jobs found gone are marked `.expired` and a `jobUnavailable` notification is posted.
    public static func checkJobs(
        _ jobs: [Job],
        store: BackgroundStore,
        session: URLSession = .shared
    ) async -> (checked: Int, unavailable: Int, marked: Int, failed: Int) {
        let eligible = jobs.filter { $0.status == .pursuing }
        guard !eligible.isEmpty else { return (0, 0, 0, 0) }

        // Extract lightweight metadata before entering async task group (avoids sending Job across actors).
        struct JobSpec: Sendable {
            let id: String
            let jobNumber: Int?
            let title: String
            let url: URL
        }
        let specs: [JobSpec] = eligible.compactMap { job in
            let urlString = JobURLPolicy.availabilityCheckURL(job: job) ?? ""
            guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
            return JobSpec(id: job.id, jobNumber: job.jobNumber, title: job.title ?? "", url: url)
        }
        guard !specs.isEmpty else { return (0, 0, 0, 0) }

        var checkedJobs: [CheckedJob] = []

        await withTaskGroup(of: CheckedJob.self) { group in
            var inFlight = 0
            let maxConcurrent = 10

            for spec in specs {
                // Wait for one result if at the concurrency limit.
                if inFlight >= maxConcurrent {
                    if let nextResult = await group.next() {
                        checkedJobs.append(nextResult)
                        inFlight -= 1
                    }
                }
                let id = spec.id
                let jobNumber = spec.jobNumber
                let title = spec.title
                let url = spec.url
                inFlight += 1
                group.addTask {
                    let checkResult = await checkURL(url, title: title, session: session)
                    return CheckedJob(jobID: id, jobNumber: jobNumber, title: title, url: url, result: checkResult)
                }
            }

            // Drain remaining tasks.
            for await groupResult in group {
                checkedJobs.append(groupResult)
            }
        }

        // Mark gone jobs.
        var markedCount = 0
        var failedCount = 0
        let unavailableCount = checkedJobs.count(where: { if case .gone = $0.result { return true }; return false })

        for checked in checkedJobs {
            if case let .gone(reason) = checked.result {
                do {
                    let idToMatch = checked.jobID
                    try await store.update(Job.self, predicate: #Predicate { $0.id == idToMatch }) { job in
                        job.status = .expired
                        job.updatedAt = Date()
                    }
                    markedCount += 1
                    // Record audit event for the auto-expiry.
                    let matchedJobs = try await store
                        .fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == idToMatch }))
                    if let job = matchedJobs.first {
                        let event = JobEvent(
                            eventType: "availability",
                            note: "Auto-expired: \(reason). Checked: \(checked.url.absoluteString)"
                        )
                        event.job = job
                        try await store.insert(event)
                    }
                    NotificationCenter.default.post(
                        name: .jobUnavailable,
                        object: nil,
                        userInfo: [
                            JobUnavailableKey.jobID: checked.jobID,
                            JobUnavailableKey.jobNumber: checked.jobNumber as Any,
                            JobUnavailableKey.title: checked.title,
                            JobUnavailableKey.reason: reason
                        ]
                    )
                } catch {
                    // A gone job we failed to mark/record is NOT a successful check — count it and
                    // log it instead of silently dropping it, so callers can surface the failure.
                    failedCount += 1
                    NSLog("AvailabilityChecker: failed to mark job \(checked.jobID) expired: \(error)")
                }
            }
        }

        return (checked: checkedJobs.count, unavailable: unavailableCount, marked: markedCount, failed: failedCount)
    }

    // MARK: - checkStaleJobs

    /// Checks jobs that haven't been touched in `staleDays` days. `limit` caps how many are checked
    /// per run; `nil` means no cap (TASK-608 — a fixed per-run cap left a large stale backlog that
    /// never fully drained, since each run only ever chipped away at the oldest slice).
    /// Throws if the underlying store fetch fails — callers must treat that as a failed check
    /// (not a zero-result success), or future checks get suppressed for the interval.
    public static func checkStaleJobs(
        store: BackgroundStore,
        staleDays: Int = 21,
        limit: Int? = nil,
        session: URLSession = .shared
    ) async throws -> (checked: Int, unavailable: Int, marked: Int, failed: Int) {
        let jobs = try await fetchStaleEligibleJobs(store: store, staleDays: staleDays, limit: limit)
        return await checkJobs(jobs, store: store, session: session)
    }

    /// Fetches jobs untouched for `staleDays` days, oldest-first, excluding terminal statuses.
    /// `limit` caps the result (`nil` = uncapped, TASK-608). Shared by the legacy silent
    /// `checkStaleJobs` and the confirm-first `maybeFindStaleGoneJobs`.
    /// Throws if the underlying store fetch fails — callers must treat that as a failed check.
    static func fetchStaleEligibleJobs(
        store: BackgroundStore,
        staleDays: Int,
        limit: Int?
    ) async throws -> [Job] {
        let cutoff = Date().addingTimeInterval(-Double(max(1, staleDays)) * 86400)

        // Use capturedAtDenormalized (populated on insert since TASK-216) to sort jobs
        // oldest-first at the DB level, bounding the query with fetchLimit when a cap is set.
        // Status and date are still filtered in-memory (enum predicates unsupported; optional
        // date comparison in predicates requires force-unwrap which SwiftData doesn't support).
        // A fetch failure propagates (do NOT swallow it as an empty result).
        var descriptor = FetchDescriptor<Job>(
            predicate: #Predicate { $0.capturedAtDenormalized != nil },
            sortBy: [SortDescriptor(\Job.capturedAtDenormalized, order: .forward)]
        )
        if let limit { descriptor.fetchLimit = limit * 4 } // over-fetch to allow for in-memory status filter
        let newStyleRows = try await store.fetch(descriptor)

        // Legacy rows with nil capturedAtDenormalized: fetch separately, filter via relationship
        var legacyDescriptor = FetchDescriptor<Job>(
            predicate: #Predicate { $0.capturedAtDenormalized == nil },
            sortBy: [SortDescriptor(\Job.createdAt, order: .forward)]
        )
        if let limit { legacyDescriptor.fetchLimit = limit * 2 }
        let legacyRows = try await store.fetch(legacyDescriptor)

        let all = newStyleRows + legacyRows
        let eligible = all.filter { job in
            guard job.status != .passed, job.status != .archived,
                  job.status != .closed, job.status != .expired else { return false }
            let ageDate = job.capturedAtDenormalized ?? job.capture?.capturedAt ?? job.createdAt
            return ageDate <= cutoff
        }
        guard let limit else { return eligible }
        return Array(eligible.prefix(limit))
    }

    /// Confirm-first background pass (TASK-595 follow-up): mirrors `maybeRunStaleCheck`'s enabled +
    /// interval gates, but returns gone CANDIDATES for the user to confirm instead of auto-expiring
    /// them. Returns nil when the check is skipped (auto-check disabled, interval not elapsed, or the
    /// store fetch failed) so the caller leaves the interval gate untouched; otherwise the (possibly
    /// empty) candidate list. `onChecked` is invoked with the completion time only after a real pass,
    /// so the caller persists `availabilityLastAutoCheckAt` exactly like the legacy path.
    public static func maybeFindStaleGoneJobs(
        store: BackgroundStore,
        settings: SettingsStore,
        session: URLSession = .shared,
        onChecked: (@Sendable (Date) async -> Void)? = nil
    ) async -> [GoneJobResult]? {
        guard settings.bool(forKey: SettingsKey.availabilityAutoCheckEnabled) else { return nil }

        let intervalDays = max(1, settings.int(forKey: SettingsKey.availabilityAutoCheckIntervalDays))
        let lastCheckStr = settings.string(forKey: SettingsKey.availabilityLastAutoCheckAt)
        if !lastCheckStr.isEmpty, let lastCheck = ISO8601DateFormatter().date(from: lastCheckStr),
           Date().timeIntervalSince(lastCheck) < Double(intervalDays) * 86400 {
            return nil
        }

        let staleDays = max(1, settings.int(forKey: SettingsKey.availabilityStaleDays))
        let jobs: [Job]
        do {
            // TASK-608: uncapped so a large stale backlog actually drains (was limited to 25/run).
            jobs = try await fetchStaleEligibleJobs(store: store, staleDays: staleDays, limit: nil)
        } catch {
            NSLog("AvailabilityChecker: stale fetch failed: \(error)")
            return nil
        }

        let found = await findGoneJobs(jobs, session: session)
        await onChecked?(Date())
        return found
    }

    // MARK: - maybeRunStaleCheck

    /// Runs stale availability check if enabled and the check interval has elapsed.
    /// - Parameter onAutoCheckCompleted: called with the completion time ONLY after a valid pass, so
    ///   the caller can persist `availabilityLastAutoCheckAt` through an explicit dependency rather
    ///   than a global notification (TASK-428). Not called when the check is skipped or the fetch
    ///   fails, so the interval gate never advances without real work.
    public static func maybeRunStaleCheck(
        store: BackgroundStore,
        settings: SettingsStore,
        session: URLSession = .shared,
        onAutoCheckCompleted: (@Sendable (Date) async -> Void)? = nil
    ) async -> (skipped: Bool, reason: String?, checked: Int, unavailable: Int, marked: Int, failed: Int) {
        // Check if auto-check is enabled.
        guard settings.bool(forKey: SettingsKey.availabilityAutoCheckEnabled) else {
            return (skipped: true, reason: "disabled", checked: 0, unavailable: 0, marked: 0, failed: 0)
        }

        // Check interval gate.
        let intervalDays = max(1, settings.int(forKey: SettingsKey.availabilityAutoCheckIntervalDays))
        let lastCheckStr = settings.string(forKey: SettingsKey.availabilityLastAutoCheckAt)
        if !lastCheckStr.isEmpty, let lastCheck = ISO8601DateFormatter().date(from: lastCheckStr) {
            let elapsed = Date().timeIntervalSince(lastCheck)
            if elapsed < Double(intervalDays) * 86400 {
                return (skipped: true, reason: "interval", checked: 0, unavailable: 0, marked: 0, failed: 0)
            }
        }

        let staleDays = max(1, settings.int(forKey: SettingsKey.availabilityStaleDays))
        let result: (checked: Int, unavailable: Int, marked: Int, failed: Int)
        do {
            // TASK-608: uncapped so a large stale backlog actually drains (was limited to 25/run).
            result = try await checkStaleJobs(store: store, staleDays: staleDays, limit: nil, session: session)
        } catch {
            // Fetch failed — no valid check ran. Do NOT invoke onAutoCheckCompleted, or the app
            // layer would advance the last-check timestamp and suppress checks for the whole interval
            // despite nothing being checked. Surface as a failed (not skipped) result.
            NSLog("AvailabilityChecker: stale check fetch failed: \(error)")
            return (skipped: false, reason: "fetch-error", checked: 0, unavailable: 0, marked: 0, failed: 0)
        }

        // Only after a valid pass: hand the completion time to the caller so it can persist
        // `availabilityLastAutoCheckAt` (TASK-428). The caller hops to the main actor as needed —
        // the checker no longer depends on a global notification observer being registered.
        await onAutoCheckCompleted?(Date())

        return (
            skipped: false,
            reason: nil,
            checked: result.checked,
            unavailable: result.unavailable,
            marked: result.marked,
            failed: result.failed
        )
    }
}

// swiftlint:enable line_length cyclomatic_complexity function_body_length large_tuple type_body_length
