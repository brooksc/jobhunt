import Foundation

// MARK: - Greenhouse

/// Wraps the existing Greenhouse board client behind the shared protocol (TASK-636).
///
/// Greenhouse is the odd one out: its ATS id (`gh:123`) doesn't carry the board, so the board is
/// *guessed* from the URL and company name and confirmed by a successful fetch. Lever and Ashby put
/// the company in the URL, so they need no guessing.
public struct GreenhouseProvider: ATSProvider {
    public let name = "Greenhouse"
    public init() {}

    public func handles(atsID: String) -> Bool {
        atsID.hasPrefix("gh:")
    }

    private func ghjid(_ atsID: String) -> String {
        String(atsID.dropFirst(3))
    }

    public func fetchPosting(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> ATSPosting? {
        let result = await GreenhouseJobBoard.fetch(
            ghjid: ghjid(atsID), company: company, urlString: urlString, session: session
        )
        guard case let .success(posting) = result else { return nil }
        return ATSPosting(
            contentPlain: GreenhouseJobBoard.plainTextDescription(posting),
            title: posting.title,
            locationName: posting.locationName,
            firstPublished: posting.firstPublished,
            updatedAt: posting.updatedAt,
            absoluteURL: posting.absoluteURL,
            providerName: name,
            boardKey: posting.board
        )
    }

    public func listOpenRoles(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> [GreenhouseJobBoard.OpenRole] {
        // Resolve the board through a posting fetch rather than guessing again — a slug that happens
        // to exist would list another company's entire board.
        let result = await GreenhouseJobBoard.fetch(
            ghjid: ghjid(atsID), company: company, urlString: urlString, session: session
        )
        guard case let .success(posting) = result else { return [] }
        return await GreenhouseJobBoard.listOpenRoles(board: posting.board, session: session)
    }

    /// Delegates to the existing checker rather than inferring from `fetchPosting`: a job-level 404
    /// only means "removed" once the *board* is confirmed to exist, otherwise a wrong board guess
    /// would 404 for every posting on it and mass-expire live jobs.
    public func isAlive(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> Bool? {
        await AvailabilityChecker.greenhouseAvailability(
            ghjid: ghjid(atsID), company: company, urlString: urlString, session: session
        )
    }

    public func fetchApplicationForm(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> ApplicationFormPreview? {
        let result = await GreenhouseJobBoard.fetch(
            ghjid: ghjid(atsID), company: company, urlString: urlString, session: session
        )
        guard case let .success(posting) = result else { return nil }
        return await GreenhouseJobBoard.fetchApplicationForm(
            board: posting.board, ghjid: ghjid(atsID), session: session
        )
    }
}

// MARK: - Lever

/// `api.lever.co/v0/postings/{company}` — public, no key (TASK-636).
///
/// Lever returns the whole board in one response and has no single-posting shortcut worth a second
/// request, so both the posting and the other-roles list come from one fetch. It publishes
/// `descriptionPlain`, so no HTML stripping is needed, and `createdAt` as epoch milliseconds. There
/// is no update timestamp at all — `PostingFreshness` handles that by falling back to first-published.
public struct LeverProvider: ATSProvider {
    public let name = "Lever"
    public init() {}

    public func handles(atsID: String) -> Bool {
        atsID.hasPrefix("lever:")
    }

    /// Our ids are `lever:{company}:{postingID}` (see `DuplicateDetector.atsPostingID`).
    static func parse(_ atsID: String) -> (company: String, postingID: String)? {
        let parts = atsID.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return (parts[1], parts[2])
    }

    public func fetchPosting(
        atsID: String, company _: String?, urlString _: String, session: URLSession
    ) async -> ATSPosting? {
        guard let parsed = Self.parse(atsID) else { return nil }
        let entries = await Self.fetchBoard(company: parsed.company, session: session)
        guard let entry = entries.first(where: { $0["id"] as? String == parsed.postingID })
        else { return nil }
        return posting(from: entry, company: parsed.company)
    }

    public func listOpenRoles(
        atsID: String, company _: String?, urlString _: String, session: URLSession
    ) async -> [GreenhouseJobBoard.OpenRole] {
        guard let parsed = Self.parse(atsID) else { return [] }
        return await Self.roles(from: Self.fetchBoard(company: parsed.company, session: session))
    }

    /// Lever returns the whole board, so a posting missing from a *non-empty* response is genuinely
    /// gone. An empty response is indeterminate: it's also what a wrong company handle returns, and
    /// two live boards checked during development returned `[]` for handles that looked plausible.
    public func isAlive(
        atsID: String, company _: String?, urlString _: String, session: URLSession
    ) async -> Bool? {
        guard let parsed = Self.parse(atsID) else { return nil }
        let entries = await Self.fetchBoard(company: parsed.company, session: session)
        guard !entries.isEmpty else { return nil }
        return entries.contains { $0["id"] as? String == parsed.postingID }
    }

    static func fetchBoard(company: String, session: URLSession) async -> [[String: Any]] {
        guard let encoded = company.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lever.co/v0/postings/\(encoded)?mode=json")
        else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Cached + coalesced: every posting on a board asks for the same board (see ATSResponseCache).
        guard let http = await ATSResponseCache.shared.response(for: request, session: session),
              http.statusCode == 200 else { return [] }
        return (try? JSONSerialization.jsonObject(with: http.body)) as? [[String: Any]] ?? []
    }

    func posting(from entry: [String: Any], company: String) -> ATSPosting? {
        let plain = (entry["descriptionPlain"] as? String) ?? ""
        let additional = (entry["additionalPlain"] as? String) ?? ""
        // `descriptionPlain` is the intro; the requirements live in `additionalPlain`. Using only the
        // first would hand extraction a posting with no requirements in it.
        let content = [plain, additional].filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !content.isEmpty else { return nil }

        let categories = entry["categories"] as? [String: Any]
        return ATSPosting(
            contentPlain: content,
            title: entry["text"] as? String,
            locationName: categories?["location"] as? String,
            firstPublished: Self.date(fromEpochMilliseconds: entry["createdAt"]),
            updatedAt: nil,
            absoluteURL: entry["hostedUrl"] as? String,
            providerName: name,
            boardKey: company
        )
    }

    static func roles(from entries: [[String: Any]]) -> [GreenhouseJobBoard.OpenRole] {
        entries.compactMap { entry in
            guard let id = entry["id"] as? String,
                  let title = (entry["text"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let url = entry["hostedUrl"] as? String, !url.isEmpty
            else { return nil }
            let categories = entry["categories"] as? [String: Any]
            return GreenhouseJobBoard.OpenRole(
                id: id,
                title: title,
                locationName: categories?["location"] as? String,
                absoluteURL: url,
                updatedAt: nil,
                firstPublished: date(fromEpochMilliseconds: entry["createdAt"])
            )
        }
    }

    /// Lever stamps `createdAt` as epoch **milliseconds**. Treating it as seconds would date every
    /// posting to 1970 and make the whole corpus look stale.
    static func date(fromEpochMilliseconds value: Any?) -> Date? {
        guard let milliseconds = value as? Double ?? (value as? Int).map(Double.init),
              milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

// MARK: - Ashby

/// `api.ashbyhq.com/posting-api/job-board/{org}` — public, no key (TASK-636).
///
/// Like Lever, one response carries the whole board. Ashby publishes `descriptionPlain` and
/// `publishedAt`, and an `isListed` flag that marks postings hidden from the public board.
public struct AshbyProvider: ATSProvider {
    public let name = "Ashby"
    public init() {}

    public func handles(atsID: String) -> Bool {
        atsID.hasPrefix("ashby:")
    }

    static func parse(_ atsID: String) -> (org: String, postingID: String)? {
        let parts = atsID.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return (parts[1], parts[2])
    }

    public func fetchPosting(
        atsID: String, company _: String?, urlString _: String, session: URLSession
    ) async -> ATSPosting? {
        guard let parsed = Self.parse(atsID) else { return nil }
        let entries = await Self.fetchBoard(org: parsed.org, session: session)
        guard let entry = entries.first(where: { $0["id"] as? String == parsed.postingID })
        else { return nil }
        return posting(from: entry, org: parsed.org)
    }

    public func listOpenRoles(
        atsID: String, company _: String?, urlString _: String, session: URLSession
    ) async -> [GreenhouseJobBoard.OpenRole] {
        guard let parsed = Self.parse(atsID) else { return [] }
        return await Self.roles(from: Self.fetchBoard(org: parsed.org, session: session))
    }

    /// As with Lever: absent from a non-empty board is removal; an empty board is indeterminate,
    /// since that's also what an unknown org returns.
    public func isAlive(
        atsID: String, company _: String?, urlString _: String, session: URLSession
    ) async -> Bool? {
        guard let parsed = Self.parse(atsID) else { return nil }
        let entries = await Self.fetchBoard(org: parsed.org, session: session)
        guard !entries.isEmpty else { return nil }
        return entries.contains { $0["id"] as? String == parsed.postingID }
    }

    static func fetchBoard(org: String, session: URLSession) async -> [[String: Any]] {
        guard let encoded = org.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.ashbyhq.com/posting-api/job-board/\(encoded)")
        else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Cached + coalesced: every posting in an org asks for the same board (see ATSResponseCache).
        guard let http = await ATSResponseCache.shared.response(for: request, session: session),
              http.statusCode == 200,
              let raw = try? JSONSerialization.jsonObject(with: http.body) as? [String: Any]
        else { return [] }
        return raw["jobs"] as? [[String: Any]] ?? []
    }

    func posting(from entry: [String: Any], org: String) -> ATSPosting? {
        guard let content = entry["descriptionPlain"] as? String, !content.isEmpty else { return nil }
        return ATSPosting(
            contentPlain: content,
            title: (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            locationName: entry["location"] as? String,
            firstPublished: (entry["publishedAt"] as? String)
                .flatMap(GreenhouseJobBoard.parseTimestamp),
            updatedAt: (entry["updatedAt"] as? String).flatMap(GreenhouseJobBoard.parseTimestamp),
            absoluteURL: entry["jobUrl"] as? String,
            providerName: name,
            boardKey: org
        )
    }

    static func roles(from entries: [[String: Any]]) -> [GreenhouseJobBoard.OpenRole] {
        entries.compactMap { entry in
            // `isListed == false` means the employer has hidden it from their own board; suggesting
            // it as an open role would be worse than omitting it.
            guard entry["isListed"] as? Bool ?? true else { return nil }
            guard let id = entry["id"] as? String,
                  let title = (entry["title"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let url = entry["jobUrl"] as? String, !url.isEmpty
            else { return nil }
            return GreenhouseJobBoard.OpenRole(
                id: id,
                title: title,
                locationName: entry["location"] as? String,
                absoluteURL: url,
                updatedAt: (entry["updatedAt"] as? String)
                    .flatMap(GreenhouseJobBoard.parseTimestamp),
                firstPublished: (entry["publishedAt"] as? String)
                    .flatMap(GreenhouseJobBoard.parseTimestamp)
            )
        }
    }
}

// MARK: - Workday

/// Workday's CXS search endpoint, which answers liveness only (TASK-636).
///
/// Workday postings are fully client-rendered, so the HTML URL returns a generic 200 shell whether
/// or not the job exists — that's how job #119 sat "available" after removal. The CXS API lists a
/// tenant's live requisitions, which settles liveness but returns no description worth using, so
/// this provider deliberately implements nothing else: a `fetchPosting` returning a search-result
/// summary would let the refresh overwrite a real capture with a stub.
public struct WorkdayProvider: ATSProvider {
    public let name = "Workday"
    public init() {}

    public func handles(atsID: String) -> Bool {
        atsID.hasPrefix("wd:")
    }

    public func fetchPosting(
        atsID _: String, company _: String?, urlString _: String, session _: URLSession
    ) async -> ATSPosting? {
        nil
    }

    public func listOpenRoles(
        atsID _: String, company _: String?, urlString _: String, session _: URLSession
    ) async -> [GreenhouseJobBoard.OpenRole] {
        []
    }

    public func isAlive(
        atsID _: String, company _: String?, urlString: String, session: URLSession
    ) async -> Bool? {
        guard let url = URL(string: urlString),
              let query = AvailabilityChecker.workdayCXSQuery(for: url) else { return nil }
        return await AvailabilityChecker.workdayReqStillListed(
            endpoint: query.endpoint, reqId: query.reqId, session: session
        )
    }
}
