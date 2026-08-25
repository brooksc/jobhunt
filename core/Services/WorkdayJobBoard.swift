import Foundation

/// Reads postings from a Workday tenant's public CXS API (TASK-690, auto-search M1).
///
/// Workday was the one vendor jobhunt could ask "is this requisition still listed?" but not "what
/// else is open here?" or "what does this posting say?" — `WorkdayProvider.listOpenRoles` returned
/// `[]` and `fetchPosting` returned `nil`. Both are implemented here.
///
/// Two endpoints, both public and key-free, verified against a live tenant on 2026-08-22:
///
///   POST  /wday/cxs/{tenant}/{site}/jobs           → paginated list, no descriptions
///   GET   /wday/cxs/{tenant}/{site}{externalPath}  → one posting, with `jobPostingInfo.jobDescription`
///
/// The pagination, retry and date handling follow `providers/workday.mjs` in the career-ops
/// project, whose comments record which live tenant motivated each rule. Where a rule looks
/// arbitrary, it isn't — the reason is in the comment.
public enum WorkdayJobBoard {
    // MARK: - Board identity

    /// The endpoints for one tenant's job site.
    public struct Board: Sendable, Equatable {
        /// Host + tenant + site, e.g. `23andme` / `23` on `23andme.wd5.myworkdayjobs.com`.
        public let tenant: String
        public let site: String
        public let host: String

        /// `POST` here for the paginated list.
        public var listEndpoint: URL? {
            URL(string: "https://\(host)/wday/cxs/\(tenant)/\(site)/jobs")
        }

        /// A posting's `externalPath` appends to this for the detail `GET`.
        public var detailBase: String {
            "https://\(host)/wday/cxs/\(tenant)/\(site)"
        }

        /// A posting's `externalPath` appends to this for the URL a human opens. Note it is
        /// relative to the *site*, not the host root — without the site segment the URL 404s.
        public var jobBase: String {
            "https://\(host)/\(site)"
        }
    }

    /// Derive the board from any URL on a Workday tenant — a posting deep link or the board's own
    /// landing page.
    ///
    /// Deliberately separate from `AvailabilityChecker.workdayCXSQuery`, which answers a different
    /// question: it requires a *posting* URL because it also extracts the requisition id. This one
    /// must accept a bare board URL too, since a user adding a search source pastes exactly that.
    /// The tenant/site halves agree by construction — both read the first host label and the
    /// first non-locale path segment.
    public static func board(for url: URL) -> Board? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased(), ATSHost.belongs(host, to: "myworkdayjobs.com"),
              let tenant = host.split(separator: ".").first.map(String.init), !tenant.isEmpty
        else { return nil }

        var segments = comps.path.split(separator: "/").map(String.init)
        // An optional locale segment (`en-US`, `fr-CA`) precedes the site on many tenants.
        if let first = segments.first, first.range(of: #"^[a-z]{2}-[A-Z]{2}$"#, options: .regularExpression) != nil {
            segments.removeFirst()
        }
        guard let site = segments.first, !site.isEmpty else { return nil }
        return Board(tenant: tenant, site: site, host: host)
    }

    // MARK: - Payload decoding

    /// Rows from one page of the list response.
    ///
    /// Reuses `GreenhouseJobBoard.OpenRole` rather than introducing a parallel type: the open-roles
    /// pane and `OpenRoleRelevance` already speak it, and a Workday-shaped twin would have to be
    /// converted at every call site.
    public static func decodeRoles(
        _ data: Data, board: Board, now: Date = Date()
    ) -> [GreenhouseJobBoard.OpenRole] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let postings = raw["jobPostings"] as? [[String: Any]] else { return [] }

        return postings.compactMap { entry in
            // A row with no path can't be opened and one with no title can't be judged — skip
            // rather than render a blank row the user can't act on (same rule as Greenhouse).
            guard let path = entry["externalPath"] as? String, !path.isEmpty,
                  let title = (entry["title"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
            else { return nil }

            // `bulletFields` carries the requisition id on every tenant seen so far; the path's
            // trailing `_R-12345` token is the fallback. The id only has to be stable and unique
            // within the board, which both are.
            let id = (entry["bulletFields"] as? [String])?.first(where: { !$0.isEmpty })
                ?? reqID(fromPath: path)
                ?? path

            return GreenhouseJobBoard.OpenRole(
                id: id,
                title: title,
                locationName: locationName(entry: entry, path: path),
                absoluteURL: board.jobBase + path,
                // Workday has no update timestamp at all — only a relative posted-on label.
                updatedAt: nil,
                firstPublished: parsePostedOn(entry["postedOn"] as? String, now: now)
            )
        }
    }

    /// `total` from the list response, when the tenant reports one.
    ///
    /// Not always truthful — see `pagesToFetch`.
    public static func decodeTotal(_ data: Data) -> Int? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return raw["total"] as? Int
    }

    /// How many postings the page carried, which is how a short page is recognised as the last one.
    public static func decodePageCount(_ data: Data) -> Int {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let postings = raw["jobPostings"] as? [[String: Any]] else { return 0 }
        return postings.count
    }

    /// The posting body, from the detail endpoint.
    ///
    /// The detail payload carries two fields the list does not — an absolute `startDate` and a
    /// structured country code — so a hydrated posting has a real first-published date rather than
    /// a rounded-off relative label.
    public static func decodePosting(_ data: Data, board: Board, urlString: String?) -> ATSPosting? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = raw["jobPostingInfo"] as? [String: Any] else { return nil }
        // As with Greenhouse: a posting with a title and no body gives a refresh nothing to do, and
        // writing an empty description over a good capture is strictly worse than leaving it.
        guard let html = info["jobDescription"] as? String, !html.isEmpty else { return nil }

        return ATSPosting(
            contentPlain: cleanDescription(visibleText: stripHtml(html)),
            title: (info["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            locationName: info["location"] as? String,
            firstPublished: (info["startDate"] as? String).flatMap(parseStartDate),
            updatedAt: nil,
            absoluteURL: (info["externalUrl"] as? String) ?? urlString,
            providerName: "Workday",
            boardKey: "\(board.tenant)/\(board.site)"
        )
    }

    // MARK: - Dates

    /// Workday publishes only a relative label: `"Posted Today"`, `"Posted Yesterday"`,
    /// `"Posted 5 Days Ago"`, `"Posted 30+ Days Ago"`.
    ///
    /// The `+` form is **unbounded** and must yield no date at all. Reading it as 30 days would
    /// invent a first-published date for a posting that could be a year old, and every freshness
    /// decision downstream would inherit the fiction.
    public static func parsePostedOn(_ label: String?, now: Date = Date()) -> Date? {
        guard let label = label?.lowercased() else { return nil }
        if label.contains("today") {
            return now
        }
        if label.contains("yesterday") {
            return now.addingTimeInterval(-86400)
        }
        guard let match = label.range(
            of: #"posted\s+(\d+)(\+?)\s*day"#, options: .regularExpression
        ) else { return nil }
        let matched = String(label[match])
        // A "30+" bucket is open-ended — no usable date.
        if matched.contains("+") {
            return nil
        }
        guard let digits = matched.range(of: #"\d+"#, options: .regularExpression),
              let days = Int(matched[digits]) else { return nil }
        return now.addingTimeInterval(-Double(days) * 86400)
    }

    /// The detail endpoint's `startDate`, a plain `yyyy-MM-dd` in the tenant's own calendar.
    public static func parseStartDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// Postings come newest-first, so pagination can stop once a page's oldest *dated* posting is
    /// well past the window — no point paying for, and rate-limit-risking, pages that are entirely
    /// stale.
    ///
    /// Two guards keep this from stopping early on good data. Undated postings are invisible here,
    /// so a page carrying none never stops the loop (that would silently truncate a tenant whose
    /// postings are all in the `30+` bucket). And the margin exists because the sort isn't
    /// perfectly monotonic: real tenants return day labels with about a day of jitter
    /// (`"27 Days Ago | 26 Days Ago | 27 Days Ago"`), so the margin has to clear that.
    static let earlyStopMargin: TimeInterval = 2 * 86400

    public static func pageIsPastWindow(
        _ roles: [GreenhouseJobBoard.OpenRole], since: Date?
    ) -> Bool {
        guard let since, !roles.isEmpty else { return false }
        let dated = roles.compactMap(\.firstPublished)
        // Every row on the page has to be dated. A page mixing old dated rows with undated ones
        // says nothing about what comes next — the undated ones could be anything — and stopping
        // there would silently truncate the tenant.
        guard dated.count == roles.count else { return false }
        // And the NEWEST row has to be outside the window, not the oldest. Keying on the oldest
        // meant a single stale outlier among otherwise fresh postings ended the scan.
        guard let newest = dated.max() else { return false }
        return newest < since.addingTimeInterval(-earlyStopMargin)
    }

    // MARK: - Pagination arithmetic

    public static let pageSize = 20

    /// How many pages to fetch in total, including the first (already-fetched) one.
    ///
    /// When the tenant reports `total`, believe it but cap it. When it doesn't, only keep going if
    /// the first page came back full — a short first page already means there is nothing more.
    ///
    /// `total` is not always honest: Workday's backend sometimes reports exactly
    /// `maxPages × pageSize` when the real count is far higher, and requests past that offset
    /// return page 0 again. The cap is what contains that, which is why it applies to the reported
    /// total rather than being bypassed by it.
    public static func pagesToFetch(total: Int?, firstPageCount: Int, maxPages: Int) -> Int {
        // A short first page is the end of the board, whatever `total` claims.
        guard firstPageCount >= pageSize else { return 1 }
        // A FULL first page means there may be more, and `total` is only advisory — the header
        // comment already records tenants reporting a `total` far below what they will serve, and
        // trusting it as a boundary means a tenant answering `total: 1` with twenty roles is
        // declared complete after one page. So a full page always justifies looking at the next
        // one; the page cap, the short-page check and the early stop are what actually bound this.
        guard let total else { return maxPages }
        let needed = Int((Double(total) / Double(pageSize)).rounded(.up))
        return max(2, min(max(needed, 2), maxPages))
    }

    // MARK: - Retry classification

    /// Whether a failed request is worth retrying: 429, any 5xx, or a transport error (no status —
    /// timeout, DNS, connection drop).
    ///
    /// A 4xx other than 429 is the server saying the request itself is wrong, and retrying it just
    /// burns the budget. This matters more than it looks: Workday's CXS API sits behind a WAF that
    /// rate-limits in bursts, and without a retry a single 429 silently truncates an entire tenant
    /// — career-ops measured a 3,383-posting tenant reduced to 20.
    public static func isRetryable(status: Int?) -> Bool {
        guard let status else { return true }
        // 408 is a timeout the server chose to report rather than drop — as transient as the
        // dropped-connection case that arrives here as a nil status.
        return status == 429 || status == 408 || status >= 500
    }

    /// A `Retry-After`, clamped.
    ///
    /// Honoured because a server telling us how long to wait knows better than a fixed backoff, and
    /// clamped because a hostile or misconfigured `Retry-After: 86400` would otherwise stall a
    /// sweep for a day. Accepts both permitted forms: delta-seconds and an HTTP-date.
    static func retryAfter(_ header: String?, maximum: Duration = .seconds(30)) -> Duration? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else {
            return nil
        }
        if let seconds = Double(header), seconds >= 0 {
            return min(.seconds(seconds), maximum)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return nil }
        return min(.seconds(max(0, date.timeIntervalSinceNow)), maximum)
    }

    // MARK: - Network

    /// Pause between successive pages *of one tenant*. A burst of same-host requests with no delay
    /// risks the WAF-level rate limiting above. Only boards that paginate past page 1 pay it.
    static let interPageDelay: Duration = .milliseconds(250)

    static let requestTimeout: TimeInterval = 20
    static let retryAttempts = 3

    /// Some tenants (seen live: geico) front CXS with bot management that 500s a request missing
    /// ordinary browser headers — no other red flag, just the absent UA and accept-language. A real
    /// Chrome UA plus a matching origin/referer clears it without per-tenant configuration.
    static func listRequest(board: Board, endpoint: URL, offset: Int) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://\(board.host)", forHTTPHeaderField: "Origin")
        request.setValue("\(board.jobBase)/", forHTTPHeaderField: "Referer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "limit": pageSize, "offset": offset, "searchText": "", "appliedFacets": [:]
        ])
        return request
    }

    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    /// One request, retried on transient failures with exponential backoff and jitter.
    ///
    /// Returns nil once the attempts are spent. The caller decides what that means — the list loop
    /// keeps the pages it already has rather than discarding the batch, which is the whole reason
    /// this doesn't throw.
    static func fetchWithRetry(
        _ request: URLRequest, session: URLSession, attempts: Int = retryAttempts
    ) async -> Data? {
        for attempt in 0 ..< attempts {
            var serverAsked: Duration?
            do {
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode
                if status == 200 {
                    return data
                }
                guard isRetryable(status: status) else { return nil }
                serverAsked = retryAfter(http?.value(forHTTPHeaderField: "Retry-After"))
            } catch {
                // Cancellation is not a transient failure — a cancelled sweep must stop, not retry.
                if error is CancellationError {
                    return nil
                }
                if (error as NSError).code == NSURLErrorCancelled {
                    return nil
                }
            }
            guard attempt < attempts - 1 else { return nil }
            // The server's own answer wins over a guess; a fixed backoff into an active rate limit
            // is how a throttle turns into a lost tenant. Jitter otherwise, so concurrent retries
            // don't re-collide in lockstep.
            let backoff = Duration.milliseconds(500 << attempt)
            let jitter = Duration.milliseconds(Int.random(in: 0 ... 250))
            try? await Task.sleep(for: serverAsked ?? (backoff + jitter))
        }
        return nil
    }

    /// Why pagination stopped. The distinction is the whole point: a run that stopped on a rate
    /// limit found *some* roles, and recording that as a healthy complete listing is how a board
    /// quietly stops being scanned properly — but a run that stopped because the caller only asked
    /// for five pages did exactly what it was told, and treating *that* as a failure marks the
    /// largest employers unreachable forever.
    public enum Stop: Sendable, Equatable {
        /// The board was read to its end.
        case complete
        /// The caller's page cap was reached with more still on the board. Expected, not an error:
        /// a market pass deliberately reads only the newest `marketPageLimit` pages.
        case bounded
        /// The tenant stopped answering partway through. A coverage failure.
        case failed(String)
    }

    public struct Listing: Sendable {
        public let roles: [GreenhouseJobBoard.OpenRole]
        public let stop: Stop
        public let reportedTotal: Int?

        /// True when the tenant broke off mid-listing — the only condition a caller should treat as
        /// a failed read.
        public var didFail: Bool {
            if case .failed = stop {
                return true
            }
            return false
        }

        /// True when this is not the whole board, for whatever reason.
        public var isPartial: Bool { stop != .complete }
    }

    /// Every posting on the board, paginating the CXS API.
    ///
    /// - Parameters:
    ///   - since: stop early once pages are entirely past this date. Nil fetches the whole board.
    ///   - maxPages: safety cap, applied regardless of what the tenant reports as `total`, so a
    ///     misbehaving API can't drive this into fetching unboundedly.
    public static func listOpenRoles(
        board: Board,
        session: URLSession = .shared,
        since: Date? = nil,
        maxPages: Int = 50,
        now: Date = Date()
    ) async -> Listing {
        guard let endpoint = board.listEndpoint else {
            return Listing(roles: [], stop: .complete, reportedTotal: nil)
        }
        guard let first = await fetchWithRetry(
            listRequest(board: board, endpoint: endpoint, offset: 0),
            session: session
        ) else {
            return Listing(roles: [], stop: .failed("didn't answer"), reportedTotal: nil)
        }

        var roles = decodeRoles(first, board: board, now: now)
        let total = decodeTotal(first)
        let pages = pagesToFetch(
            total: total, firstPageCount: decodePageCount(first), maxPages: max(1, maxPages)
        )
        if pageIsPastWindow(roles, since: since) {
            return Listing(roles: roles, stop: .complete, reportedTotal: total)
        }
        // A short first page is the whole board. Checked explicitly because the loop below never
        // runs in that case, and inferring "complete" from the loop falling through would report a
        // one-page board — including an empty one — as bounded.
        if decodePageCount(first) < pageSize {
            return Listing(roles: roles, stop: .complete, reportedTotal: total)
        }

        // Sequential, not concurrent: one tenant's API has no reason to receive a burst of parallel
        // requests, and a mid-run failure stops cleanly with the pages already gathered instead of
        // discarding all of them.
        var page = 1
        // Running the loop to exhaustion means the page budget ran out, not that the board ended;
        // the two `break`s below are the paths that prove we reached the end.
        var stop = Stop.bounded
        while page < pages {
            if Task.isCancelled {
                return Listing(roles: roles, stop: .failed("cancelled"), reportedTotal: total)
            }
            try? await Task.sleep(for: interPageDelay)
            let request = listRequest(board: board, endpoint: endpoint, offset: page * pageSize)
            guard let data = await fetchWithRetry(request, session: session) else {
                return Listing(
                    roles: roles,
                    stop: .failed("stopped answering after \(roles.count) roles"),
                    reportedTotal: total
                )
            }
            let pageRoles = decodeRoles(data, board: board, now: now)
            roles.append(contentsOf: pageRoles)
            // A short page is the last page, whatever `total` claimed.
            if decodePageCount(data) < pageSize {
                stop = .complete
                break
            }
            if pageIsPastWindow(pageRoles, since: since) {
                stop = .complete
                break
            }
            page += 1
        }
        return Listing(roles: roles, stop: stop, reportedTotal: total)
    }

    /// One posting's full detail, including the description the list endpoint omits.
    public static func fetchPosting(
        board: Board, externalPath: String, session: URLSession = .shared, urlString: String? = nil
    ) async -> ATSPosting? {
        guard let url = URL(string: board.detailBase + externalPath) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("\(board.jobBase)/", forHTTPHeaderField: "Referer")
        guard let data = await fetchWithRetry(request, session: session) else { return nil }
        return decodePosting(data, board: board, urlString: urlString)
    }

    // MARK: - Path helpers

    /// The location a Workday URL encodes as `/job/{Location-Slug}/{title-slug}`.
    ///
    /// Only the segment right after `/job/` is read, never the whole URL — scanning the full URL
    /// would match company slugs and ATS subdomains by accident, so a tenant with "india" in its
    /// hostname would look like an Indian posting.
    public static func locationFromPath(_ path: String) -> String? {
        let segments = path.split(separator: "/").map(String.init)
        guard let idx = segments.lastIndex(of: "job"), idx + 1 < segments.count else { return nil }
        let raw = segments[idx + 1].removingPercentEncoding ?? segments[idx + 1]
        let spaced = raw.replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return spaced.isEmpty ? nil : spaced
    }

    /// Some tenants report a rolled-up display string (`"5 Locations"`) while the canonical URL
    /// still names the primary one, and others omit `locationsText` entirely. Fall back to the path
    /// in both cases — otherwise no location filter can ever match those postings.
    static func locationName(entry: [String: Any], path: String) -> String? {
        let text = (entry["locationsText"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty, !isLocationRollup(text) {
            return text
        }
        return locationFromPath(path) ?? text
    }

    /// `"5 Locations"` / `"2 locations"` — a count, not a place.
    static func isLocationRollup(_ text: String) -> Bool {
        text.range(of: #"^\d+\s+locations?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The trailing `_R-12345` requisition token of a posting path.
    static func reqID(fromPath path: String) -> String? {
        guard let last = path.split(separator: "/").last,
              let underscore = last.lastIndex(of: "_") else { return nil }
        var id = String(last[last.index(after: underscore)...])
        // Workday appends a `-N` posting index on re-posted requisitions.
        if let dash = id.range(of: #"-\d+$"#, options: .regularExpression) {
            id.removeSubrange(dash)
        }
        return id.isEmpty ? nil : id
    }
}
