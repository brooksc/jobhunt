import Foundation

/// What a source needs configured, which is also what the add-source form has to ask for.
public enum SourceConfiguration: Sendable, Equatable {
    /// A company board slug — Greenhouse, Lever, Ashby. Resolvable from a company name.
    case perCompany(slugHint: String)
    /// A tenant URL. Workday's `{tenant}.{instance}.myworkdayjobs.com/{site}` triple cannot be
    /// derived from a company name — there is no rule that turns "Acme" into `acme.wd5`, so the
    /// user pastes the board URL and the form says so.
    case boardURL(hint: String)
}

/// Why a sweep produced nothing.
///
/// The whole point of the type is that **`[]` is not an error**. A board that migrated ATS doesn't
/// fail — it answers 200 with an empty list, forever. Collapsing "reachable and empty" into the
/// same outcome as "unreachable" is how a source goes quiet for weeks without anything on screen
/// saying so, which is the failure mode the health tracking exists to catch.
public enum SourceError: Error, Sendable, Equatable {
    /// The config doesn't name a board this source can reach.
    case misconfigured(String)
    /// DNS, TLS, timeout, or a status that isn't 200 after retries.
    case unreachable(String)
    /// 200, but not in a shape this source recognises.
    case malformedResponse(String)
}

/// Everything a source needs to find its board.
public struct SourceConfig: Sendable, Equatable, Codable {
    /// A Greenhouse board slug, a Lever company handle, an Ashby org, or a Workday board URL.
    public var slug: String
    /// The employer name, for postings whose board payload doesn't carry one. Greenhouse's list
    /// endpoint doesn't.
    public var company: String?
    /// How deep to paginate, for the vendors that paginate at all (only Workday does).
    ///
    /// Exists because the two callers want opposite things. A *watched company* wants the whole
    /// board — the user asked for that employer specifically. A *market pass* re-reads 12,884
    /// Workday tenants every day and only needs what's new, so paying for 2,000 postings per tenant
    /// turns a daily sweep into a four-day one. Nil means the source's own default.
    public var pageLimit: Int?

    public init(slug: String, company: String? = nil, pageLimit: Int? = nil) {
        self.slug = slug
        self.company = company
        self.pageLimit = pageLimit
    }
}

/// A source that can be swept for postings without knowing about any specific posting (TASK-691, M2).
///
/// Sibling to `ATSProvider`, which stays as it is. That protocol is posting-centric — every method
/// takes an `atsID`, and even its listing call resolves the board *through* a known posting. That's
/// right for refresh and availability, but discovery has no posting to start from: it starts from a
/// company. Hence a second protocol rather than more conformances to the first.
public protocol JobSource: Sendable {
    /// Stable identifier persisted on the source row. Must not change once shipped.
    var id: String { get }
    /// The vendor's own name, shown to the user.
    var displayName: String { get }
    var configuration: SourceConfiguration { get }

    /// Every posting the board currently lists.
    ///
    /// `since` is a hint, not a filter: sources that can stop paginating early should, and the
    /// caller still applies the age criterion itself. Implementations must **not** issue a request
    /// per posting — a description belongs here only when the list payload carried it for free.
    /// One extra round trip per row is 6,000 requests an hour at real board sizes.
    func fetchRecent(
        config: SourceConfig, since: Date?, session: URLSession
    ) async throws -> [DiscoveredPosting]
}

// MARK: - Shared transport

enum JobSourceTransport {
    /// A board fetch that reports *why* it failed, unlike the `ATSProvider` fetches which return
    /// `[]` for everything. Discovery needs the distinction; refresh legitimately doesn't.
    static func fetchJSON(
        _ url: URL, session: URLSession, timeout: TimeInterval = 20
    ) async -> Result<Data, SourceError> {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        // Cached and coalesced, same as the ATSProvider board fetches — a sweep and an open-roles
        // pane asking for the same board within the TTL should cost one request.
        guard let http = await ATSResponseCache.shared.response(for: request, session: session) else {
            return .failure(.unreachable("no response from \(url.host ?? "board")"))
        }
        guard http.statusCode == 200 else {
            return .failure(.unreachable("HTTP \(http.statusCode) from \(url.host ?? "board")"))
        }
        return .success(http.body)
    }

    /// The dedup key plus the fields every adapter fills the same way.
    static func posting(
        from role: GreenhouseJobBoard.OpenRole,
        sourceID: String,
        company: String?,
        description: String? = nil
    ) -> DiscoveredPosting? {
        // A row we can't key can't be deduped, and ingesting it would re-create the same job on
        // every sweep. Dropping it is the lesser failure.
        guard let key = DiscoveredPosting.dedupKey(for: role.absoluteURL) else { return nil }
        return DiscoveredPosting(
            dedupKey: key,
            url: role.absoluteURL,
            title: role.title,
            company: company,
            locationRaw: role.locationName,
            firstPublished: role.firstPublished,
            descriptionPlain: description,
            sourceID: sourceID
        )
    }
}

// MARK: - Greenhouse

/// `boards-api.greenhouse.io/v1/boards/{board}/jobs` — public, no key.
///
/// The list endpoint publishes no description, no salary and no departments, so gate A sees only
/// title and location for this vendor. That's not a gap to fix here: fetching bodies for every row
/// is exactly what the pre-gate no-network rule forbids, and hydration covers the survivors.
public struct GreenhouseSource: JobSource {
    public let id = "greenhouse"
    public let displayName = "Greenhouse"
    public let configuration = SourceConfiguration.perCompany(slugHint: "board slug, e.g. “gitlab”")
    public init() {}

    public func fetchRecent(
        config: SourceConfig, since _: Date?, session: URLSession
    ) async throws -> [DiscoveredPosting] {
        guard let encoded = config.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !config.slug.isEmpty,
              let url = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(encoded)/jobs")
        else { throw SourceError.misconfigured("“\(config.slug)” isn't a usable Greenhouse board slug") }

        let data = try await JobSourceTransport.fetchJSON(url, session: session).get()
        return GreenhouseJobBoard.decodeRoles(data).compactMap {
            JobSourceTransport.posting(from: $0, sourceID: id, company: config.company)
        }
    }
}

// MARK: - Lever

/// `api.lever.co/v0/postings/{company}` — public, no key.
///
/// Lever returns the whole board in one response *including* the description, so gate A can see the
/// body for free here. `descriptionPlain` is the intro and `additionalPlain` the requirements —
/// joining them matters, because the intro alone is marketing copy.
public struct LeverSource: JobSource {
    public let id = "lever"
    public let displayName = "Lever"
    public let configuration = SourceConfiguration.perCompany(slugHint: "company handle, e.g. “netflix”")
    public init() {}

    public func fetchRecent(
        config: SourceConfig, since _: Date?, session: URLSession
    ) async throws -> [DiscoveredPosting] {
        guard let encoded = config.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !config.slug.isEmpty,
              let url = URL(string: "https://api.lever.co/v0/postings/\(encoded)?mode=json")
        else { throw SourceError.misconfigured("“\(config.slug)” isn't a usable Lever company handle") }

        let data = try await JobSourceTransport.fetchJSON(url, session: session).get()
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw SourceError.malformedResponse("Lever returned something that isn't a board")
        }
        return entries.compactMap { entry -> DiscoveredPosting? in
            guard let role = LeverProvider.roles(from: [entry]).first else { return nil }
            let body = [entry["descriptionPlain"] as? String, entry["additionalPlain"] as? String]
                .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: "\n\n")
            return JobSourceTransport.posting(
                from: role, sourceID: id, company: config.company,
                description: body.isEmpty ? nil : body
            )
        }
    }
}

// MARK: - Ashby

/// `api.ashbyhq.com/posting-api/job-board/{org}` — public, no key.
///
/// Like Lever, the board payload carries the description. Unlike Lever, some rows are `isListed:
/// false` — hidden by the employer from their own board — and `LeverProvider`-style decoding
/// already drops those.
public struct AshbySource: JobSource {
    public let id = "ashby"
    public let displayName = "Ashby"
    public let configuration = SourceConfiguration.perCompany(slugHint: "org name, e.g. “ramp”")
    public init() {}

    public func fetchRecent(
        config: SourceConfig, since _: Date?, session: URLSession
    ) async throws -> [DiscoveredPosting] {
        guard let encoded = config.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !config.slug.isEmpty,
              let url = URL(string: "https://api.ashbyhq.com/posting-api/job-board/\(encoded)")
        else { throw SourceError.misconfigured("“\(config.slug)” isn't a usable Ashby org") }

        let data = try await JobSourceTransport.fetchJSON(url, session: session).get()
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = raw["jobs"] as? [[String: Any]]
        else { throw SourceError.malformedResponse("Ashby returned something that isn't a board") }

        return entries.compactMap { entry -> DiscoveredPosting? in
            guard let role = AshbyProvider.roles(from: [entry]).first else { return nil }
            let body = entry["descriptionPlain"] as? String
            return JobSourceTransport.posting(
                from: role, sourceID: id, company: config.company,
                description: (body?.isEmpty ?? true) ? nil : body
            )
        }
    }
}

// MARK: - Workday

/// A Workday tenant's CXS API — see `WorkdayJobBoard`.
///
/// The odd one out in two ways. The config is a board URL, not a slug, because the
/// tenant/instance/site triple can't be derived from a company name. And a sweep can legitimately
/// come back truncated (a rate limit mid-pagination), which is neither success nor failure: the
/// roles gathered so far are real, so they're returned, and only a truncation with *nothing*
/// gathered is reported as unreachable.
public struct WorkdaySource: JobSource {
    public let id = "workday"
    public let displayName = "Workday"
    public let configuration = SourceConfiguration.boardURL(
        hint: "board URL, e.g. https://acme.wd5.myworkdayjobs.com/careers"
    )
    /// Higher than the open-roles pane's cap: a sweep wants the whole board, and large tenants run
    /// to thousands of postings. Still a cap — a misbehaving API must not be able to paginate
    /// forever.
    public static let sweepMaxPages = 100

    public init() {}

    public func fetchRecent(
        config: SourceConfig, since: Date?, session: URLSession
    ) async throws -> [DiscoveredPosting] {
        guard let url = URL(string: config.slug), let board = WorkdayJobBoard.board(for: url) else {
            throw SourceError.misconfigured("“\(config.slug)” isn't a Workday board URL")
        }
        let listing = await WorkdayJobBoard.listOpenRoles(
            board: board, session: session, since: since,
            maxPages: config.pageLimit ?? Self.sweepMaxPages
        )
        if listing.roles.isEmpty, listing.truncated {
            throw SourceError.unreachable("\(board.tenant) didn't answer")
        }
        return listing.roles.compactMap {
            JobSourceTransport.posting(
                from: $0, sourceID: id, company: config.company ?? board.tenant
            )
        }
    }
}

// MARK: - Registry

public enum JobSources {
    public static let all: [any JobSource] = [
        GreenhouseSource(), LeverSource(), AshbySource(), WorkdaySource()
    ]

    public static func source(id: String) -> (any JobSource)? {
        all.first { $0.id == id }
    }
}
