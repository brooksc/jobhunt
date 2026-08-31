// swiftlint:disable line_length large_tuple type_body_length file_length
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

// MARK: - Unverified jobs

/// Why a job's availability could not be established. A check that can't reach the real page is NOT
/// evidence the posting is live, but it was previously reported the same way (silently dropped), so a
/// sweep that verified nothing looked identical to one that verified everything.
public enum UnverifiedReason: String, Sendable, CaseIterable {
    /// Cloudflare / bot-challenge interstitial — the real page is never served to a background request.
    case botChallenge
    /// Client-rendered shell whose HTML is identical for live and removed postings.
    case unreadablePage
    /// LinkedIn rate-limited us, so the rest of the LinkedIn pass was abandoned this run.
    case rateLimited
    /// Outside this run's LinkedIn rotation window — it gets checked on a later run.
    case notCheckedThisRun
    /// Network failure, timeout, or a refused (internal-host) URL.
    case unreachable
    /// The job has no usable URL to check.
    case noURL

    /// User-facing phrasing for the confirmation sheet.
    public var summary: String {
        switch self {
        case .botChallenge: "blocked by bot protection"
        case .unreadablePage: "page can't be read reliably"
        case .rateLimited: "LinkedIn rate-limited the check"
        case .notCheckedThisRun: "not due for checking this run"
        case .unreachable: "site couldn't be reached"
        case .noURL: "no URL to check"
        }
    }

    /// Reads back what `AvailabilitySweep.outcomes` persisted for an unverified job.
    ///
    /// The stored detail is the raw case, not the sentence, so a drain that resumes after a relaunch
    /// can tell "LinkedIn hasn't got to it yet" from "the page can't be read" — a decision that must
    /// not hinge on user-facing phrasing that could be reworded at any time. Rows written before that
    /// change hold the sentence itself, hence the nil.
    public static func stored(_ detail: String?) -> UnverifiedReason? {
        detail.flatMap { UnverifiedReason(rawValue: $0) }
    }

    /// What to show for a stored detail: the sentence for a known case, otherwise the string as
    /// written — which covers both a gone reason (free text) and a row from before the change.
    public static func displaySummary(for detail: String) -> String {
        UnverifiedReason(rawValue: detail)?.summary ?? detail
    }
}

/// A job whose availability the sweep could not determine either way.
public struct UnverifiedJobResult: Sendable {
    public let jobID: String
    public let jobNumber: Int?
    public let company: String?
    public let title: String
    public let url: URL?
    public let reason: UnverifiedReason
    /// The raw diagnostic (host, status, message) — shown as detail, not as the headline.
    public let detail: String

    public init(
        jobID: String, jobNumber: Int?, company: String?, title: String,
        url: URL?, reason: UnverifiedReason, detail: String
    ) {
        self.jobID = jobID
        self.jobNumber = jobNumber
        self.company = company
        self.title = title
        self.url = url
        self.reason = reason
        self.detail = detail
    }
}

/// The full outcome of an availability sweep: what was found gone, and what could not be checked.
/// Returning both means the UI can say "12 checked, 3 couldn't be verified" instead of implying the
/// unverified ones are fine.
public struct AvailabilitySweep: Sendable {
    public let gone: [GoneJobResult]
    public let unverified: [UnverifiedJobResult]
    /// Job ids this run confirmed are still listed.
    ///
    /// A run has always reported what it FOUND wrong; recording what it confirmed is what makes two
    /// runs comparable, and what lets a row say when it was last checked (TASK-674).
    public let alive: [String]
    /// How many jobs this run actually reached the network for.
    ///
    /// The UI used to derive this as `handedIn - unverified.count`, which assumes the checker looked
    /// at everything it was given. When a status filter inside `findGoneJobs` silently dropped 584
    /// archived jobs, that arithmetic produced "All 584 postings in view are still available" from a
    /// run that made zero requests. A count the checker reports itself can't be talked into an
    /// all-clear it didn't earn.
    public let checkedCount: Int

    public init(
        gone: [GoneJobResult],
        unverified: [UnverifiedJobResult] = [],
        checkedCount: Int = 0,
        alive: [String] = []
    ) {
        self.gone = gone
        self.unverified = unverified
        self.checkedCount = checkedCount
        self.alive = alive
    }

    /// Every job this run reached a conclusion about, ready to persist (TASK-674).
    ///
    /// Includes the unverified ones deliberately: "we couldn't check this" is itself worth recording,
    /// so a posting that has been unreachable for weeks is visible as such rather than looking like
    /// one that was simply never due.
    public var outcomes: [AvailabilityOutcome] {
        gone.map { AvailabilityOutcome(jobID: $0.jobID, verdict: .gone, detail: $0.reason) }
            + alive.map { AvailabilityOutcome(jobID: $0, verdict: .alive, detail: nil) }
            // The raw case, not its sentence: this is the record a resumed drain reads to decide
            // whether the job is still worth re-asking about (TASK-673). The UI resolves it back
            // through `UnverifiedReason.displaySummary(for:)`.
            + unverified.map {
                AvailabilityOutcome(jobID: $0.jobID, verdict: .unverified, detail: $0.reason.rawValue)
            }
    }

    /// Counts per reason, most common first — what the "unable to check" line is built from.
    public var unverifiedByReason: [(reason: UnverifiedReason, count: Int)] {
        Dictionary(grouping: unverified, by: \.reason)
            .map { (reason: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $0.reason.rawValue) > ($1.count, $1.reason.rawValue) }
    }

    /// One sentence for the UI, or nil when everything was verified.
    public var unverifiedSummary: String? {
        guard !unverified.isEmpty else { return nil }
        let parts = unverifiedByReason.map { "\($0.count) \($0.reason.summary)" }
        let count = unverified.count
        return "Unable to check \(count) job\(count == 1 ? "" : "s") — \(parts.joined(separator: ", "))."
    }
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
        // NOTE: bare "page not found" removed (TASK-626, job #325) — generic 404-shell copy, not job-scoped.
        "job not found", "job no longer available",
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
        // "<subject> not found" — "page" removed (TASK-626, job #325): "page not found" is generic 404 copy.
        #"\b(job|position|posting|listing)\s+not\s+found\b"#
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
        if path.isEmpty {
            path = "/"
        }
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
                (codePoint >= 48 && codePoint <= 57) {
                return Character(scalar)
            } // a-z, 0-9
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
        if orig.absoluteString == final.absoluteString {
            return false
        }

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

    /// True for loopback / link-local / private-range hosts that the availability check must not fetch
    /// (SSRF guard, F8). Recognizes `localhost`, `.local`/`.internal` suffixes, IPv4 literals in the
    /// loopback (127/8, 0/8), link-local (169.254/16) and private (10/8, 172.16/12, 192.168/16) ranges,
    /// and IPv6 loopback/link-local/unique-local literals. Hostnames that *resolve* to private IPs are
    /// not caught here — a full guard would require DNS resolution.
    static func isInternalHost(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "localhost" || h.hasSuffix(".localhost") || h.hasSuffix(".local") || h.hasSuffix(".internal") {
            return true
        }
        if h.contains(":") { // IPv6 literal
            return h == "::1" || h.hasPrefix("fe80") || h.hasPrefix("fc") || h.hasPrefix("fd")
        }
        let octets = h.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0 ... 255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (127, _): return true
        case (169, 254): return true
        case (192, 168): return true
        case (172, 16 ... 31): return true
        default: return false
        }
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
        if ATSHost.belongs(host, to: "greenhouse.io"),
           components.queryItems?.contains(where: { $0.name == "error" && $0.value == "true" }) ?? false {
            return true
        }
        // Workable: redirect to the `/oops` error landing.
        if host.contains("workable.com"), path == "/oops" {
            return true
        }
        return false
    }

    /// Registrable hosts that serve a client-rendered SPA shell whose STATIC HTML embeds job-state UI
    /// templates ("expired", "…was closed", an expired-job apply button) for every job — so body-based
    /// gone detection is unreliable and must be skipped for them (TASK-637). Extend as new such
    /// aggregators/SPAs surface. Status-code (404/410) and redirect signals still apply.
    static let bodyUnreliableHosts: Set<String> = ["jobright.ai"]

    static func isBodyUnreliableHost(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        let registrable = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return bodyUnreliableHosts.contains(registrable)
            || bodyUnreliableHosts.contains { registrable.hasSuffix(".\($0)") }
    }

    /// Whether a URL points at LinkedIn.
    ///
    /// Exact host or a true subdomain — NOT a suffix match, which would also accept `notlinkedin.com`
    /// and `linkedin.com.evil.example`. Used to caution the user before expiring a LinkedIn posting:
    /// its signed-out pages are the least trustworthy "gone" signal we have (job #566 was listed as
    /// gone while still live).
    public static func isLinkedInURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "linkedin.com" || host.hasSuffix(".linkedin.com")
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
        // Exact host or true subdomain via the shared helper. `contains("linkedin.com")` also matched
        // notlinkedin.com and linkedin.com.evil.example — the marker check made that low-risk, but a
        // host test shouldn't be the loose part of a rule that expires the user's jobs.
        guard let url = URL(string: finalURLString), isLinkedInURL(url) else { return false }
        return body.contains("closed-job__flavor")
    }

    /// True when the response is a Cloudflare / bot-challenge interstitial rather than the real page.
    /// Career sites on Phenom (e.g. `pinterestcareers.com`, job #48) sit behind Cloudflare, which
    /// serves a "Just a moment…" challenge (HTTP 403) to a plain background request — the actual
    /// posting is never delivered, so its availability is genuinely indeterminate. `body` MUST already
    /// be lowercased. Scoped to the challenge markers so an ordinary 403 without a challenge falls
    /// through to the normal heuristics.
    static func isBotChallenge(_ body: String) -> Bool {
        if body.contains("just a moment") {
            return true
        }
        if body.contains("challenge-platform") || body.contains("cf-mitigated") ||
            body.contains("_cf_chl_opt") || body.contains("cf-challenge") {
            return true
        }
        if body.contains("attention required") && body.contains("cloudflare") {
            return true
        }
        return false
    }

    /// LinkedIn `…/jobs/search|collections/…?currentJobId=N` URLs point at a results page that only
    /// highlights a job — the posting's closed banner isn't in that response, so a removed posting reads
    /// as available (jobs #218/#224). Rewrite them to the public view `…/jobs/view/N`, where the banner
    /// IS served and `bodyGoneReason`/`isLinkedInClosedJob` can see it. Non-matching URLs are unchanged.
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
              let host = comps.host?.lowercased(), ATSHost.belongs(host, to: "myworkdayjobs.com"),
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
               bullets.contains(where: { $0.lowercased() == idLower }) {
                return true
            }
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
        if authFragments.contains(where: { path.contains($0) }) {
            return true
        }
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

        // SSRF guard (CWE-918): a captured job's URL / <link rel="canonical"> is attacker-controlled and
        // this default-on background loop fetches it (following redirects). Refuse loopback, link-local,
        // and private hosts so it can't be turned into a request against the local machine or LAN.
        // (Covers IP-literal / localhost / .local hosts; hostname→private DNS rebinding and redirects to
        // internal hosts are not covered here.) TASK-644 review / F8.
        if let host = requestURL.host, isInternalHost(host) {
            return .unverifiable(reason: "refusing to fetch internal host: \(host)")
        }

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
            let body = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            // 1.9 Cloudflare / bot-challenge interstitial (Pinterest etc., jobs #48/#122): the real page
            // is never served at ANY status, so it's indeterminate, NOT gone. Checked before gone heuristics.
            if isBotChallenge(body) {
                return .unverifiable(reason: "bot challenge: \(finalURLString)")
            }

            // 1. Gone status codes — including LinkedIn. The earlier "LinkedIn 404 is unverifiable" carve-out
            // (meant to protect live search-only postings) suppressed REAL removals: with the app's browser
            // User-Agent, LinkedIn's guest /jobs/view returns a clean 404 for a removed posting (verified
            // against LinkedIn's guest job API — 404 there too), while live postings return 200. So a 404
            // is a reliable gone signal; treat it as such (TASK-639, job #212). Rate-limit/bot-block
            // statuses (429/999) aren't in goneStatusCodes, so they fall through to .available, never gone.
            if goneStatusCodes.contains(statusCode) {
                return .gone(reason: "HTTP \(statusCode)")
            }

            // 1.5 Applicant-tracking board "posting not found" landing (e.g. Greenhouse redirects a
            // removed posting to `…/{board}?error=true` at HTTP 200). Deterministic gone signal.
            if isBoardErrorLandingURL(finalURLString) {
                return .gone(reason: "board posting not found: \(finalURLString)")
            }

            // 1.6 Client-rendered SPA / aggregator shells (jobright.ai; same class as Cribl #325) embed
            // job-state templates ("expired", "…was closed") in their STATIC HTML for every job, so the
            // body heuristics below would false-positive on live jobs. A real removal on these hosts also
            // just returns the 200 shell, so availability is genuinely unverifiable — never gone. (A hard
            // 404/410 was already handled above and still counts.) See TASK-637.
            if isBodyUnreliableHost(finalURLString) {
                return .unverifiable(reason: "client-rendered shell (body not authoritative): \(finalURLString)")
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
    /// One job's availability-check inputs (Sendable so it crosses the task-group boundary).
    /// Internal rather than private so `RunPlan` — which is what decides the numbers every surface
    /// shows — can hold them and be unit-tested.
    /// A job's availability-relevant fields, detached from SwiftData (TASK-705).
    ///
    /// **The crash this exists to prevent.** `Job` is a `@Model`, so it is not `Sendable` and stays
    /// bound to the `ModelContext` that fetched it. `BackgroundStore.fetch` returns `sending [T]`,
    /// which satisfies the compiler by transferring *ownership of the array* — but the elements
    /// still point back at the store actor's context. Reading a lazy relationship such as
    /// `job.capture` from another thread therefore faults through that context off-actor, and doing
    /// it while the actor is materialising rows (`reconcileOrphanedExtractions`) and SwiftUI's
    /// `@Query` is reading the main context corrupts the heap:
    ///
    ///     ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
    ///     Job.capture.getter → JobURLPolicy.availabilityCheckURL → AvailabilityChecker.plan
    ///
    /// It aborted on launch, intermittently, because all three had to overlap.
    ///
    /// Every field the availability pass needs — including the two URLs behind `capture` — is
    /// resolved once, on the isolation that owns the model, and nothing downstream touches a live
    /// row. `BackgroundStore.swift` already stated this rule for the LLM queue (TASK-526); the
    /// availability path predates it and was never brought across.
    public struct JobInput: Sendable {
        public let id: String
        public let jobNumber: Int?
        public let company: String?
        public let title: String?
        public let status: JobStatus
        public let applicationURL: String?
        public let captureURL: String?
        public let captureCanonicalURL: String?
        /// `capturedAtDenormalized ?? capture.capturedAt ?? createdAt`, resolved on-actor because the
        /// middle term is a relationship fault.
        public let ageDate: Date

        /// **Call only on the isolation that owns `job`** — the store actor for a fetched row, the
        /// main actor for a `@Query` row. This is the one place a live model is read.
        public init(job: Job) {
            id = job.id
            jobNumber = job.jobNumber
            company = job.company
            title = job.title
            status = job.status
            applicationURL = job.applicationURL
            let capture = job.capture
            captureURL = capture?.url
            captureCanonicalURL = capture?.canonicalURL
            ageDate = job.capturedAtDenormalized ?? capture?.capturedAt ?? job.createdAt
        }

        /// Same precedence as `JobURLPolicy.availabilityCheckURL(job:)`, over detached fields.
        public var availabilityCheckURL: String? {
            JobURLPolicy.applicationURL(
                applicationURL: applicationURL,
                canonicalURL: captureCanonicalURL,
                captureURL: captureURL
            )
        }
    }

    struct JobSpec {
        let id: String
        let jobNumber: Int?
        let company: String?
        let title: String
        let url: URL
        /// The posting's ATS id (from any of the job's URLs) for the authoritative confirm-alive
        /// override — Greenhouse, Lever, Ashby or Workday (TASK-631, generalized by TASK-636).
        let atsID: String?
    }

    /// Delay between serial LinkedIn availability checks to stay under LinkedIn's rate limit (TASK-641).
    static let linkedInPaceDelay: Duration = .milliseconds(500)

    /// Max LinkedIn postings checked per run — capped + shuffled so a run can't fire a bursty volume
    /// that trips LinkedIn's rate limit; coverage rotates across runs (eventual, not per-run — TASK-643).
    static let maxLinkedInPerRun = 12

    /// The window of LinkedIn postings to check this run: a stable order rotated by a caller-persisted
    /// cursor.
    ///
    /// This replaced a random `shuffle()`. Shuffling samples with replacement across runs, so with ~100
    /// LinkedIn jobs at 12 per run some postings were re-checked repeatedly while others went many runs
    /// untouched — a removed posting could sit undetected indefinitely (job #132). Rotating a stable
    /// order visits every posting exactly once per ceil(count / cap) runs. Same request volume and
    /// pacing, so the rate-limit protection of TASK-643 is unchanged.
    static func linkedInSlice<T>(_ specs: [T], offset: Int, id: (T) -> String) -> [T] {
        guard !specs.isEmpty else { return [] }
        let ordered = specs.sorted { id($0) < id($1) } // stable across runs, unlike shuffle
        guard ordered.count > maxLinkedInPerRun else { return ordered }
        let start = ((offset % ordered.count) + ordered.count) % ordered.count // tolerate negatives
        let wrapped = ordered[start...] + ordered[..<start]
        return Array(wrapped.prefix(maxLinkedInPerRun))
    }

    /// Race-free monotonic counter so the two interleaved availability passes report one progress stream.
    private actor CheckCounter {
        private var count = 0
        func next() -> Int {
            count += 1; return count
        }
    }

    /// Outcome of a LinkedIn guest-API check. `.throttled` (rate-limit / block / network error) means we
    /// can't confirm removal — the caller stops checking LinkedIn for the rest of the run (backoff).
    /// `.live` carries the job id for the same reason `SpecOutcome.live` does — a confirmed-listed
    /// posting is a result to record, not a non-event (TASK-674).
    ///
    /// `.indeterminate` exists because "couldn't prove gone" is NOT "confirmed alive" (TASK-674.01).
    /// While a sweep only reported problems, collapsing the two was harmless; now that a verdict is
    /// persisted and shown as "Still listed", it would be a claim the check never earned — the same
    /// false confidence that let a run which checked nothing report an all-clear. Distinct from
    /// `.throttled`, which additionally means "stop the LinkedIn pass".
    private enum LinkedInOutcome {
        case gone(GoneJobResult), live(String), indeterminate(String), throttled
    }

    /// One spec's contribution to the sweep: gone, verified-live, or verified-nothing.
    /// `.live` carries the job id because a still-listed posting is a RESULT worth recording, not
    /// merely the absence of a problem — without it, a run could say what it found but never what it
    /// confirmed, and no two runs could be compared (TASK-674).
    private enum SpecOutcome { case gone(GoneJobResult), live(String), unverified(UnverifiedJobResult) }

    private static func unverified(
        _ spec: JobSpec, _ reason: UnverifiedReason, _ detail: String
    ) -> UnverifiedJobResult {
        UnverifiedJobResult(
            jobID: spec.id, jobNumber: spec.jobNumber, company: spec.company,
            title: spec.title, url: spec.url, reason: reason, detail: detail
        )
    }

    /// Check one non-LinkedIn spec (the concurrent pass) and apply the ATS confirm-alive override;
    /// reports gone only when the posting is genuinely gone, and reports *why* when it couldn't be
    /// checked. LinkedIn is handled separately, gently.
    private static func goneResult(for spec: JobSpec, session: URLSession) async -> SpecOutcome {
        // Ask the posting's own ATS first when we can. It answers definitively in BOTH directions,
        // whereas the page heuristics can only recognise removal wording a JS shell never renders.
        if let atsID = spec.atsID, let provider = ATSRegistry.provider(forATSID: atsID),
           let alive = await provider.isAlive(
               atsID: atsID, company: spec.company,
               urlString: spec.url.absoluteString, session: session
           ) {
            guard alive else {
                return .gone(GoneJobResult(
                    jobID: spec.id, jobNumber: spec.jobNumber, company: spec.company,
                    title: spec.title, url: spec.url,
                    reason: "\(provider.name.lowercased()) posting \(atsID) no longer listed"
                ))
            }
            return .live(spec.id)
        }
        let result = await checkURL(spec.url, title: spec.title, session: session)
        let reason: String
        switch result {
        case let .gone(goneReason):
            reason = goneReason
        case .available:
            return .live(spec.id)
        case let .unverifiable(detail):
            // The distinction the user sees: a challenge page vs a page we can't trust.
            let why: UnverifiedReason = detail.hasPrefix("bot challenge")
                ? .botChallenge
                : (detail.hasPrefix("refusing to fetch") ? .unreachable : .unreadablePage)
            return .unverified(unverified(spec, why, detail))
        case let .error(error):
            return .unverified(unverified(spec, .unreachable, error.localizedDescription))
        }
        // The TASK-631 alive-override that used to sit here is gone: a Greenhouse posting is now
        // resolved authoritatively up front, so reaching this point means there was no usable gh_jid.
        return .gone(GoneJobResult(
            jobID: spec.id, jobNumber: spec.jobNumber, company: spec.company,
            title: spec.title, url: spec.url, reason: reason
        ))
    }

    /// The LinkedIn numeric posting id from a `?currentJobId=` search/collections deep-link or a
    /// `/jobs/view/{id}` URL (TASK-642).
    static func linkedInJobID(from url: URL) -> String? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if let id = comps.queryItems?.first(where: { $0.name.lowercased() == "currentjobid" })?.value,
           !id.isEmpty, id.allSatisfy(\.isNumber) {
            return id
        }
        let segments = comps.path.split(separator: "/").map(String.init)
        if let idx = segments.firstIndex(of: "view"), idx + 1 < segments.count,
           !segments[idx + 1].isEmpty, segments[idx + 1].allSatisfy(\.isNumber) {
            return segments[idx + 1]
        }
        return nil
    }

    /// Availability for a LinkedIn posting via the guest job API (`jobs-guest/jobs/api/jobPosting/{id}`):
    /// a clean 404/410 means removed; a 200 posting is live unless its body carries the closed banner or
    /// a gone phrase; a throttle/block (429/999) or network error is `.throttled` — can't confirm, and
    /// signals the caller to back off. A rate-limited check therefore never false-expires (TASK-642/643).
    private static func linkedInOutcome(for spec: JobSpec, session: URLSession) async -> LinkedInOutcome {
        guard let jobID = linkedInJobID(from: spec.url),
              let apiURL = URL(string: "https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/\(jobID)") else {
            // Nothing to ask about: no posting id could be parsed from the URL. That is not
            // evidence the posting is live.
            return .indeterminate("no LinkedIn posting id in the URL")
        }
        var request = URLRequest(url: apiURL, timeoutInterval: timeoutSeconds)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .throttled // network error → back off
        }
        func gone(_ reason: String) -> LinkedInOutcome {
            .gone(GoneJobResult(
                jobID: spec.id, jobNumber: spec.jobNumber, company: spec.company,
                title: spec.title, url: spec.url, reason: reason
            ))
        }
        switch http.statusCode {
        case 404, 410:
            return gone("linkedin posting \(jobID) removed (guest API \(http.statusCode))")
        case 200:
            let body = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            // A 200 with an empty body tells us nothing either way.
            guard !body.isEmpty else { return .indeterminate("empty response from LinkedIn") }
            if isLinkedInClosedJob(finalURLString: apiURL.absoluteString, body: body) || bodyGoneReason(body) != nil {
                return gone("linkedin posting \(jobID) no longer accepting applications")
            }
            return .live(spec.id)
        case 429, 999:
            return .throttled // rate-limited / blocked
        default:
            // An unexpected status is not an answer; don't flag it gone, and don't claim it live.
            return .indeterminate("unexpected HTTP \(http.statusCode) from LinkedIn")
        }
    }

    /// The concurrent (non-LinkedIn) availability pass — up to 10 in flight. Reports each completion.
    private static func checkConcurrently(
        _ specs: [JobSpec], session: URLSession, tick: @Sendable @escaping () async -> Void
    ) async -> AvailabilitySweep {
        var gone: [GoneJobResult] = []
        var blocked: [UnverifiedJobResult] = []
        var alive: [String] = []
        func record(_ outcome: SpecOutcome) {
            switch outcome {
            case let .gone(result): gone.append(result)
            case let .unverified(result): blocked.append(result)
            case let .live(jobID): alive.append(jobID)
            }
        }
        await withTaskGroup(of: SpecOutcome.self) { group in
            var inFlight = 0
            for spec in specs {
                if inFlight >= 10 {
                    if let done = await group.next() {
                        record(done)
                        inFlight -= 1
                        await tick()
                    }
                }
                inFlight += 1
                group.addTask { await goneResult(for: spec, session: session) }
            }
            for await done in group {
                record(done)
                await tick()
            }
        }
        return AvailabilitySweep(
            gone: gone, unverified: blocked, checkedCount: specs.count - blocked.count, alive: alive
        )
    }

    /// The gentle LinkedIn pass: one at a time with a pace gap, stopping the moment LinkedIn throttles
    /// so we never hammer it (TASK-643). Runs interleaved with `checkConcurrently` for wall-clock spread.
    private static func checkLinkedInPaced(
        _ specs: [JobSpec], session: URLSession, tick: @Sendable @escaping () async -> Void
    ) async -> AvailabilitySweep {
        var gone: [GoneJobResult] = []
        var skipped: [UnverifiedJobResult] = []
        var alive: [String] = []
        for (index, spec) in specs.enumerated() {
            if Task.isCancelled {
                // Report the untouched remainder rather than letting a cancelled run look complete.
                skipped += specs[index...].map { unverified($0, .notCheckedThisRun, "run cancelled") }
                break
            }
            let outcome = await linkedInOutcome(for: spec, session: session)
            if case let .gone(result) = outcome {
                gone.append(result)
            }
            if case let .live(jobID) = outcome {
                alive.append(jobID)
            }
            if case let .indeterminate(why) = outcome {
                skipped.append(unverified(spec, .unreadablePage, why))
            }
            await tick()
            if case .throttled = outcome {
                // LinkedIn is rate-limiting — stop; the rest are picked up on a future run. Advance the
                // progress counter for the skipped ones so the bar still completes.
                skipped += specs[index...].map { unverified($0, .rateLimited, "LinkedIn throttled the check") }
                for _ in (index + 1) ..< specs.count {
                    await tick()
                }
                break
            }
            try? await Task.sleep(for: linkedInPaceDelay)
        }
        return AvailabilitySweep(
            gone: gone, unverified: skipped, checkedCount: specs.count - skipped.count, alive: alive
        )
    }

    /// `findGoneJobs` with the LinkedIn rotation cursor read and advanced, so successive runs cover
    /// different postings. Every caller should use this rather than `findGoneJobs` directly — if the
    /// cursor never advances, the same LinkedIn window is re-checked forever.
    public static func findGoneJobsRotating(
        _ jobs: [JobInput],
        settings: SettingsStore,
        restrictToStatuses: Set<JobStatus>? = scheduledSweepStatuses,
        session: URLSession = .shared,
        onProgress: (@Sendable (_ checked: Int, _ total: Int) async -> Void)? = nil
    ) async -> AvailabilitySweep {
        let offset = settings.int(forKey: SettingsKey.linkedInRotationOffset)
        let results = await findGoneJobs(
            jobs,
            restrictToStatuses: restrictToStatuses,
            session: session,
            linkedInOffset: offset,
            onProgress: onProgress
        )
        // Advance by the cap regardless of how many LinkedIn jobs existed this run; the slice applies
        // modulo, so an over-large cursor simply wraps.
        settings.setInt(offset &+ maxLinkedInPerRun, forKey: SettingsKey.linkedInRotationOffset)
        return results
    }

    /// Which statuses the **scheduled** sweep is allowed to check.
    ///
    /// Interested (`.pursuing`) and Applied both qualify: a role you applied to can be pulled just as
    /// a saved one can. Interview/offer/rejected stay protected — a job you're actively interviewing
    /// for belongs in `.interview`, not `.applied` — and terminal statuses are already excluded
    /// upstream by `fetchStaleEligibleJobs`.
    public static let scheduledSweepStatuses: Set<JobStatus> = [.pursuing, .applied]

    /// - Parameter restrictToStatuses: statuses this run may check, or `nil` to check every job
    ///   handed in. **`nil` is for callers that have already chosen the scope themselves** — the
    ///   on-demand, view-scoped check does, and passing anything else there silently discards the
    ///   user's selection. The default keeps the scheduled sweep's protected statuses.
    ///
    ///   This started as an unconditional `filter` here as well as at every call site. When the Jobs
    ///   list began checking the view rather than a hardcoded status pair, this copy silently
    ///   discarded all 584 archived jobs and the run reported "All 584 postings in view are still
    ///   available" — a false all-clear, which is the worst answer this function can give. Hence a
    ///   parameter: the scope is now stated by the caller, once.
    public static func findGoneJobs(
        _ jobs: [JobInput],
        restrictToStatuses: Set<JobStatus>? = scheduledSweepStatuses,
        session: URLSession = .shared,
        linkedInOffset: Int = 0,
        onProgress: (@Sendable (_ checked: Int, _ total: Int) async -> Void)? = nil
    ) async -> AvailabilitySweep {
        let plan = plan(for: jobs, restrictToStatuses: restrictToStatuses, linkedInOffset: linkedInOffset)
        guard !plan.isEmpty else { return AvailabilitySweep(gone: [], unverified: plan.uncheckable) }

        let concurrentSpecs = plan.concurrent
        let linkedInSpecs = plan.linkedIn
        let linkedInThisRun = plan.linkedInThisRun
        let uncheckable = plan.uncheckable
        let total = plan.checkCount

        let counter = CheckCounter()
        @Sendable func tick() async {
            let n = await counter.next()
            await onProgress?(n, total)
        }

        // Interleave the two passes so LinkedIn's paced requests are spread across the run rather than
        // bunched. Each pass keeps its own results (no shared mutable state); progress is merged via the
        // actor-backed counter.
        async let concurrentResults = checkConcurrently(concurrentSpecs, session: session, tick: tick)
        async let linkedInResults = checkLinkedInPaced(linkedInThisRun, session: session, tick: tick)

        // LinkedIn coverage is eventual, not per-run (TASK-643): everything outside this run's window
        // is genuinely unchecked, and saying so is the difference between "nothing was gone" and
        // "we only looked at 12 of your 21 LinkedIn postings".
        let checkedIDs = Set(linkedInThisRun.map(\.id))
        let deferred = linkedInSpecs
            .filter { !checkedIDs.contains($0.id) }
            .map { unverified($0, .notCheckedThisRun, "outside this run's LinkedIn rotation window") }

        let concurrent = await concurrentResults
        let linkedIn = await linkedInResults
        return AvailabilitySweep(
            gone: concurrent.gone + linkedIn.gone,
            unverified: uncheckable + concurrent.unverified + linkedIn.unverified + deferred,
            checkedCount: concurrent.checkedCount + linkedIn.checkedCount,
            alive: concurrent.alive + linkedIn.alive
        )
    }

    // MARK: - Greenhouse authoritative availability (TASK-631)

    /// The Greenhouse posting id (`gh_jid`) found in the first of `urls` that carries one, via the shared
    /// ATS-id extraction (handles both `?gh_jid=N` on career sites and `/jobs/N` on greenhouse.io hosts).
    public static func greenhouseJobID(fromURLs urls: [String?]) -> String? {
        for case let urlString? in urls {
            if let ats = DuplicateDetector.atsPostingID(urlString: urlString), ats.hasPrefix("gh:") {
                return String(ats.dropFirst(3))
            }
        }
        return nil
    }

    /// Candidate Greenhouse board tokens to try for a posting, best-guess first. A `*.greenhouse.io`
    /// URL carries the board authoritatively in its path; otherwise derive it from the career-site host
    /// (stripping suffixes like "careers"/"jobs" — `pinterestcareers` → `pinterest`) and the normalized
    /// company name. Deduped, order preserved.
    public static func greenhouseBoardCandidates(company: String?, urlString: String) -> [String] {
        var candidates: [String] = []
        if let comps = URLComponents(string: urlString), let host = comps.host?.lowercased() {
            if ATSHost.belongs(host, to: "greenhouse.io") {
                if let board = comps.path.split(separator: "/").map(String.init).first, !board.isEmpty {
                    candidates.append(board)
                }
            } else {
                let labels = host.split(separator: ".").map(String.init)
                let registrable = labels.count >= 2 ? labels[labels.count - 2] : (labels.first ?? "")
                if !registrable.isEmpty {
                    for suffix in ["careers", "career", "jobs", "job", "careersite", "work", "talent"]
                        where registrable.count > suffix.count && registrable.hasSuffix(suffix) {
                        candidates.append(String(registrable.dropLast(suffix.count)))
                    }
                    candidates.append(registrable)
                }
            }
        }
        if let company {
            let slug = String(String.UnicodeScalarView(
                company.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            ))
            if !slug.isEmpty {
                candidates.append(slug)
            }
        }
        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Authoritative availability for a Greenhouse-backed posting: `true` alive, `false` removed,
    /// `nil` when no board could be resolved.
    ///
    /// This used to be consulted ONLY to veto a would-be-gone HTML result, which meant a board whose
    /// career page never *looks* gone could never be detected at all. Nebius (#341) is exactly that:
    /// `careers.nebius.com/?gh_jid=…` serves a 754 KB JavaScript shell at HTTP 200 with no removal
    /// wording for a posting the Greenhouse API reports as `404 Job not found`. The definitive answer
    /// was sitting there unread.
    ///
    /// A job 404 is only trusted once the BOARD itself resolves. Guessing the board slug from the
    /// company name is inherently fallible, and without that guard a wrong guess would 404 for every
    /// posting on it and mass-expire live jobs.
    static func greenhouseAvailability(
        ghjid: String, company: String?, urlString: String, session: URLSession = .shared
    ) async -> Bool? {
        for board in greenhouseBoardCandidates(company: company, urlString: urlString).prefix(4) {
            guard let url = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(board)/jobs/\(ghjid)")
            else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            // Through the cache: the same board is asked about repeatedly within a sweep, and a
            // throttled answer here doesn't merely fail — it demotes the job from "gone" to
            // "couldn't verify", which is what made consecutive runs disagree.
            guard let http = await ATSResponseCache.shared.response(for: request, session: session)
            else { continue }
            if http.statusCode == 200 {
                return true
            }
            // Not 404 (rate limit, 5xx, network hiccup) tells us nothing — try the next candidate.
            guard http.statusCode == 404 else { continue }
            if await greenhouseBoardExists(board, session: session) {
                return false
            }
        }
        return nil
    }

    /// Whether a Greenhouse board slug is real, so a job-level 404 can be read as "removed" rather
    /// than "wrong board".
    private static func greenhouseBoardExists(_ board: String, session: URLSession) async -> Bool {
        guard let url = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(board)") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // Cached: this is asked once per JOB but answers a question about the BOARD, so a sweep over
        // 73 Greenhouse postings across 59 boards repeated it needlessly.
        guard let http = await ATSResponseCache.shared.response(for: request, session: session)
        else { return false }
        return http.statusCode == 200
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
        _ jobs: [JobInput],
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
            let urlString = job.availabilityCheckURL ?? ""
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
        let unavailableCount = checkedJobs.count(where: {
            if case .gone = $0.result {
                return true
            }; return false
        })

        let (marked, failed) = await markGone(checkedJobs, store: store)
        markedCount += marked
        failedCount += failed

        return (
            checked: checkedJobs.count, unavailable: unavailableCount,
            marked: markedCount, failed: failedCount
        )
    }

    /// Persist the verdicts a check produced: expire each gone job, record an audit event, and
    /// announce it. Split from `checkJobs` because gathering verdicts over the network and writing
    /// them to the store are two phases that share nothing but the array between them.
    private static func markGone(
        _ checkedJobs: [CheckedJob], store: BackgroundStore
    ) async -> (marked: Int, failed: Int) {
        var markedCount = 0
        var failedCount = 0
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
        return (markedCount, failedCount)
    }

    // MARK: - Run planning

    /// Exactly what a run will and won't check, decided once.
    ///
    /// The UI and the run used to work this out separately: the menu counted checkable jobs (400),
    /// the run then counted what it would actually fetch (342), and the progress dialog reported a
    /// third number. Every one was correct and the difference was legitimate — LinkedIn is checked
    /// twelve per run by rotation — but three numbers for one operation reads as a bug, and a user
    /// who can't reconcile them stops trusting the result. One planner, one set of numbers.
    struct RunPlan {
        /// Non-LinkedIn specs, checked concurrently.
        let concurrent: [JobSpec]
        /// Every LinkedIn spec, in or out of this run's window.
        let linkedIn: [JobSpec]
        /// The LinkedIn slice this run will actually check.
        let linkedInThisRun: [JobSpec]
        /// Jobs with no usable URL — reported, never silently dropped.
        let uncheckable: [UnverifiedJobResult]

        /// How many jobs this run will fetch. The number every surface should show.
        var checkCount: Int {
            concurrent.count + linkedInThisRun.count
        }

        /// LinkedIn postings held back for a later run.
        var deferredLinkedInCount: Int {
            linkedIn.count - linkedInThisRun.count
        }

        var isEmpty: Bool {
            concurrent.isEmpty && linkedInThisRun.isEmpty
        }
    }

    static func plan(
        for jobs: [JobInput],
        restrictToStatuses: Set<JobStatus>? = scheduledSweepStatuses,
        linkedInOffset: Int
    ) -> RunPlan {
        let eligible = restrictToStatuses.map { allowed in
            jobs.filter { allowed.contains($0.status) }
        } ?? jobs

        // Jobs with no usable URL can't be checked at all — previously dropped silently.
        var uncheckable: [UnverifiedJobResult] = []
        let specs: [JobSpec] = eligible.compactMap { job in
            let urlString = job.availabilityCheckURL ?? ""
            guard !urlString.isEmpty, let url = URL(string: urlString) else {
                uncheckable.append(UnverifiedJobResult(
                    jobID: job.id, jobNumber: job.jobNumber, company: job.company,
                    title: job.title ?? "", url: nil, reason: .noURL,
                    detail: urlString.isEmpty ? "no URL recorded" : "unparseable URL"
                ))
                return nil
            }
            // The ATS id usually lives in the capture URL (a `?gh_jid=` the canonicalized
            // applicationURL may have dropped), so scan all of the job's known URLs.
            let atsID = ATSRegistry.resolve(
                urls: [job.captureURL, job.applicationURL, job.captureCanonicalURL]
            )?.atsID
            return JobSpec(
                id: job.id, jobNumber: job.jobNumber, company: job.company,
                title: job.title ?? "", url: url, atsID: atsID
            )
        }

        /// LinkedIn aggressively rate-limits a burst of guest requests (999/blocked/redirect), which reads
        /// as "available" and misses removed postings (job #212). We stay guest-only (no login → no
        /// account-ban risk) and instead check LinkedIn GENTLY: capped + rotated per run so a run can't
        /// fire a bursty volume, paced one-at-a-time, run INTERLEAVED with the other (concurrent) checks
        /// for wall-clock spread, and backed off the moment LinkedIn throttles. LinkedIn coverage is
        /// therefore eventual across runs, not guaranteed in one (TASK-643).
        func isLinkedIn(_ spec: JobSpec) -> Bool {
            isLinkedInHost(spec.url)
        }
        let linkedInSpecs = specs.filter(isLinkedIn)
        return RunPlan(
            concurrent: specs.filter { !isLinkedIn($0) },
            linkedIn: linkedInSpecs,
            linkedInThisRun: linkedInSlice(linkedInSpecs, offset: linkedInOffset, id: \.id),
            uncheckable: uncheckable
        )
    }

    /// How many postings a run would check, and how many it would hold back.
    public struct RunSummary: Sendable, Equatable {
        public let checking: Int
        public let deferredLinkedIn: Int

        public init(checking: Int, deferredLinkedIn: Int) {
            self.checking = checking
            self.deferredLinkedIn = deferredLinkedIn
        }
    }

    /// What the next on-demand run over `jobs` will check, for a caller that has to *state* it before
    /// starting — the menu label.
    ///
    /// **Counts only.** `plan` builds a full `JobSpec` per job, and resolving each posting's ATS id
    /// costs regex work over three URLs — 60ms for 400 jobs, which a menu label was paying on every
    /// body evaluation, on the main thread. None of it is needed to answer "how many?": the LinkedIn
    /// slice is always `min(count, cap)` long, so the two numbers follow from the URLs alone.
    ///
    /// The cap and the LinkedIn test are the same ones `plan` uses, and
    /// `testSummaryAgreesWithTheFullPlan` pins the two together — a count that drifts from the run is
    /// the bug this whole API exists to prevent.
    public static func plannedRun(for jobs: [Job], settings _: SettingsStore) -> RunSummary {
        var linkedIn = 0
        var other = 0
        for job in jobs {
            guard let urlString = JobURLPolicy.availabilityCheckURL(job: job),
                  let url = URL(string: urlString) else { continue }
            if isLinkedInHost(url) {
                linkedIn += 1
            } else {
                other += 1
            }
        }
        return RunSummary(
            checking: other + min(linkedIn, maxLinkedInPerRun),
            deferredLinkedIn: max(0, linkedIn - maxLinkedInPerRun)
        )
    }

    /// Shared by the planner and the counter so "is this LinkedIn?" can't be answered two ways.
    static func isLinkedInHost(_ url: URL) -> Bool {
        (url.host?.lowercased() ?? "").hasSuffix("linkedin.com")
    }

    // MARK: - On-demand, view-scoped checking

    /// Which of `jobs` an on-demand check should actually fetch.
    ///
    /// The Jobs list checks what it is currently showing, so this is the rule that decides what a
    /// view's worth of rows costs in requests. It exists mainly for the **Archived** view: `.archived`
    /// is a terminal status, so `fetchStaleEligibleJobs` skips it and nothing in the app ever checks
    /// an archived posting. That left no way to find out which of several hundred archived jobs are
    /// dead — which is the first thing you want to know before deciding whether any of the rest are
    /// worth reconsidering under a better extraction and scoring prompt.
    ///
    /// Excluded: `.expired` (re-confirming a dead posting is dead costs a request and changes
    /// nothing), `.duplicate` (the surviving job is the one that matters), and anything `JobURLPolicy`
    /// won't give a URL for (it cannot be checked at all). Everything else in view is fair game —
    /// deliberately including `.archived`, which is the entire point.
    public static func checkableJobs(from jobs: [Job]) -> [Job] {
        jobs.filter { job in
            guard job.status != .expired, job.status != .duplicate else { return false }
            return JobURLPolicy.availabilityCheckURL(job: job) != nil
        }
    }

    /// Whether an on-demand run over `checked` also did the scheduled sweep's work.
    ///
    /// The scheduled sweep watches Interested and Applied jobs. An on-demand check over some other
    /// view — the Archived one above, say — proves nothing about those, so the caller must not reset
    /// the sweep's interval on the strength of it, or the jobs the user is actually pursuing go
    /// unchecked for a day because they looked at their archive.
    public static func coversScheduledSweep(checked: [Job], allJobs: [Job]) -> Bool {
        let checkedIDs = Set(checked.map(\.id))
        let scheduled = allJobs.filter { $0.status == .pursuing || $0.status == .applied }
        guard !scheduled.isEmpty else { return false }
        return scheduled.allSatisfy { checkedIDs.contains($0.id) }
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

    /// Fetches jobs untouched for `staleDays` days, oldest-first, excluding terminal statuses. `limit`
    /// caps the result (`nil` = uncapped, TASK-608). `alwaysCheckStatuses` are re-checked every run
    /// regardless of age (TASK-621 — pursued jobs expire before the staleness window). Throws on fetch
    /// failure; callers must treat that as a failed check.
    static func fetchStaleEligibleJobs(
        store: BackgroundStore,
        staleDays: Int,
        limit: Int?,
        alwaysCheckStatuses: Set<String> = []
    ) async throws -> [JobInput] {
        // Fetch, filter and detach all happen INSIDE the actor. The filter reads
        // `capture?.capturedAt`, a lazy relationship, so running it on the returned array — as this
        // did — faults through the store's context off-actor. See `JobInput`.
        try await store.staleAvailabilityInputs(
            staleDays: staleDays, limit: limit, alwaysCheckStatuses: alwaysCheckStatuses
        )
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
    ) async -> AvailabilitySweep? {
        guard settings.bool(forKey: SettingsKey.availabilityAutoCheckEnabled) else { return nil }

        let intervalDays = max(1, settings.int(forKey: SettingsKey.availabilityAutoCheckIntervalDays))
        let lastCheckStr = settings.string(forKey: SettingsKey.availabilityLastAutoCheckAt)
        if !lastCheckStr.isEmpty, let lastCheck = ISO8601DateFormatter().date(from: lastCheckStr),
           Date().timeIntervalSince(lastCheck) < Double(intervalDays) * 86400 {
            return nil
        }

        let staleDays = max(1, settings.int(forKey: SettingsKey.availabilityStaleDays))
        let jobs: [JobInput]
        do {
            // TASK-608: uncapped so a large stale backlog drains. TASK-621: always re-check pursued jobs.
            jobs = try await fetchStaleEligibleJobs(
                store: store, staleDays: staleDays, limit: nil, alwaysCheckStatuses: ["pursuing", "applied"]
            )
        } catch {
            NSLog("AvailabilityChecker: stale fetch failed: \(error)")
            return nil
        }

        let found = await findGoneJobsRotating(jobs, settings: settings, session: session)
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

// swiftlint:enable line_length large_tuple type_body_length file_length
