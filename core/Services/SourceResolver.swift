import Foundation

/// What a probe of one candidate board found.
public enum ProbeOutcome: Sendable, Equatable {
    /// The board exists and lists this many open roles. Only ≥1 counts as a resolution.
    case listing(count: Int)
    /// The board answered, with nothing on it. Real, and not the same as absent: a company between
    /// hiring rounds has an empty board that will fill up again.
    case empty
    /// The vendor said no such board. An answer, not a hiccup — re-probing will say the same.
    case absent
    /// Couldn't tell. A timeout, a DNS failure, a 5xx. Distinct from `absent` because the user
    /// pruning a list has to be able to tell "this company has no board" from "the network
    /// hiccuped", and a retry only helps for one of them.
    case unknown(String)
}

/// One board that might belong to a company.
public struct ResolvedBoard: Sendable, Equatable {
    /// `JobSource.id`.
    public let kind: String
    public let displayName: String
    /// What goes in `SourceConfig.slug`.
    public let slug: String
    /// Where a human would look.
    public let boardURL: String
    public let jobCount: Int
    /// The employer this board belongs to, as best the URL can say — what to offer as the source's
    /// name and `SourceConfig.company`.
    ///
    /// Separate from `slug` because for Workday the slug **is the whole URL**: the tenant, site and
    /// host are all config the adapter needs. Using the slug as the name meant a pasted Workday
    /// link became the company on every job discovered through it — `SourceConfig.company` is what
    /// the adapter prefers over the board's own tenant, so rows read
    /// "https://acme.wd5.myworkdayjobs.com/careers" where the employer should be.
    public let suggestedCompany: String

    public init(
        kind: String, displayName: String, slug: String, boardURL: String, jobCount: Int,
        suggestedCompany: String? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.slug = slug
        self.boardURL = boardURL
        self.jobCount = jobCount
        self.suggestedCompany = suggestedCompany ?? slug
    }
}

/// Why nothing resolved. The wording matters: each of these sends the user somewhere different.
public enum ResolutionFailure: Sendable, Equatable {
    /// Every vendor said no such board.
    case noBoardFound
    /// A board exists but lists nothing right now. Worth keeping — it will fill up.
    case boardsFoundButEmpty([ResolvedBoard])
    /// At least one probe couldn't answer, so absence was never established.
    case inconclusive(String)
    /// The name can't be turned into a slug at all.
    case unusableName(String)
}

public enum ResolutionResult: Sendable, Equatable {
    case resolved(ResolvedBoard)
    case failed(ResolutionFailure)
}

/// Finds a company's job board from its name (TASK-694, M5).
///
/// This is the difference between a tool for people who know what a Greenhouse board slug is and
/// one anybody can use. It's also what stops the feature rotting: in career-ops' own data 13 of 87
/// boards had migrated ATS and were silently returning nothing for weeks, and re-resolution
/// recovered 8 of them — one going from 0 to 53 open roles.
///
/// Ported from `discover-ats.mjs`, including the rule that makes it trustworthy: **a board counts
/// as resolved only when it exists *and* lists at least one job.** A vendor URL that merely fails
/// to 404 is how dead slugs get saved, and a dead slug looks exactly like a company that stopped
/// hiring.
public enum SourceResolver {
    /// Vendors are probed in this order and the first match wins, so a resolvable company pays only
    /// for the vendors ahead of its own. Greenhouse first because it's the most common by a wide
    /// margin; Workday is absent because a name can't produce one (see `resolve(boardURL:)`).
    public static let probeOrder = ["greenhouse", "ashby", "lever"]

    /// The characters a slug may contain before it's interpolated into a URL. **This is the SSRF
    /// choke point** — `/`, `@`, `:` and friends are what would let a company name smuggle in a
    /// different host. Mixed case is deliberate: Ashby board slugs are case-sensitive.
    static let allowedSlugCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
    )

    /// "Acme Corp, Inc." → "acme-corp-inc".
    ///
    /// Lossy on purpose: this is a guess, and the probe is what decides whether the guess was right.
    public static func deriveSlug(_ name: String) -> String {
        let lowered = name.lowercased()
        let dashed = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return String(dashed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    static func isSafeSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.unicodeScalars.allSatisfy { allowedSlugCharacters.contains($0) }
    }

    /// The board URL a human would open, per vendor.
    static func boardURL(kind: String, slug: String) -> (url: String, host: String)? {
        switch kind {
        case "greenhouse": ("https://job-boards.greenhouse.io/\(slug)", "job-boards.greenhouse.io")
        case "ashby": ("https://jobs.ashbyhq.com/\(slug)", "jobs.ashbyhq.com")
        case "lever": ("https://jobs.lever.co/\(slug)", "jobs.lever.co")
        default: nil
        }
    }

    /// Build a candidate URL, refusing anything whose host isn't exactly what was intended.
    ///
    /// Defence in depth: `isSafeSlug` already forbids the characters that could smuggle in a host,
    /// and this re-parses the result to confirm it. Two checks rather than one because the guarantee
    /// has to survive a future edit to `boardURL` that someone makes without reading this comment.
    static func candidate(kind: String, slug: String) -> ResolvedBoard? {
        guard isSafeSlug(slug), let built = boardURL(kind: kind, slug: slug),
              let parsed = URL(string: built.url), parsed.host?.lowercased() == built.host,
              let source = JobSources.source(id: kind)
        else { return nil }
        return ResolvedBoard(
            kind: kind, displayName: source.displayName, slug: slug,
            boardURL: built.url, jobCount: 0
        )
    }

    // MARK: - Probing

    /// Ask one vendor whether it has this board, and how many roles are on it.
    public static func probe(
        kind: String, slug: String, session: URLSession = .shared
    ) async -> ProbeOutcome {
        // Workday gets its own path because a full sweep paginates up to 100 pages, and the question
        // here is only "is anything on this board" — one page answers it, and asking a tenant for
        // 3,000 postings to find that out would be rude.
        if kind == "workday" {
            guard let url = URL(string: slug), let board = WorkdayJobBoard.board(for: url) else {
                return .unknown("“\(slug)” isn't a Workday board URL")
            }
            let listing = await WorkdayJobBoard.listOpenRoles(
                board: board, session: session, maxPages: 1
            )
            if !listing.roles.isEmpty {
                // `max`, not `??`: the tenant's own total underreports — one answering `total: 1`
                // while serving a full page is real — so trusting it here would tell the user a
                // 3,000-role board has one opening while we are holding twenty of them.
                return .listing(count: max(listing.reportedTotal ?? 0, listing.roles.count))
            }
            // Keyed on a genuine failure, not on partialness: this asks for one page, so a board
            // with nothing on it always "stopped short" — and reporting a real empty board as
            // unreachable would tell the user their correct URL was broken.
            if case let .failed(why) = listing.stop {
                return .unknown("\(board.tenant) \(why)")
            }
            return .empty
        }

        guard let source = JobSources.source(id: kind) else {
            return .unknown("no source of kind “\(kind)”")
        }
        do {
            let postings = try await source.fetchRecent(
                config: SourceConfig(slug: slug), since: nil, session: session
            )
            return postings.isEmpty ? .empty : .listing(count: postings.count)
        } catch let SourceError.unreachable(detail) {
            // A 404 is the vendor answering "no such board" — definitive, and worth distinguishing
            // from a timeout so the UI doesn't suggest a retry that can never succeed.
            return detail.contains("404") ? .absent : .unknown(detail)
        } catch let SourceError.misconfigured(detail) {
            return .unknown(detail)
        } catch {
            return .unknown("the board didn't answer")
        }
    }

    /// Find a company's board by name.
    ///
    /// Probes sequentially and stops at the first hit. Concurrency would be faster and is not worth
    /// it: the common case resolves on the first probe, and a company that resolves on Greenhouse
    /// should not be sending requests to Ashby and Lever for no reason.
    public static func resolve(
        companyName: String, session: URLSession = .shared
    ) async -> ResolutionResult {
        let slug = deriveSlug(companyName)
        guard isSafeSlug(slug) else {
            return .failed(.unusableName(
                "“\(companyName)” doesn't contain anything usable as a board name"
            ))
        }

        var empties: [ResolvedBoard] = []
        var inconclusive: String?
        for kind in probeOrder {
            guard let candidate = candidate(kind: kind, slug: slug) else { continue }
            switch await probe(kind: kind, slug: slug, session: session) {
            case let .listing(count):
                return .resolved(ResolvedBoard(
                    kind: candidate.kind, displayName: candidate.displayName, slug: slug,
                    boardURL: candidate.boardURL, jobCount: count
                ))
            case .empty:
                empties.append(candidate)
            case .absent:
                continue
            case let .unknown(detail):
                // One probe that never answered is enough to leave the question open: absence was
                // not established, so "no board found" would be a claim we can't make.
                inconclusive = inconclusive ?? detail
            }
        }

        if !empties.isEmpty {
            return .failed(.boardsFoundButEmpty(empties))
        }
        if let inconclusive {
            return .failed(.inconclusive(inconclusive))
        }
        return .failed(.noBoardFound)
    }

    // MARK: - Resolving a pasted URL

    /// Identify and verify a board from a URL the user pasted.
    ///
    /// The other half of making this usable: a user who can't name their ATS can still copy the
    /// address of the careers page they're looking at. It's also the only way to add a Workday
    /// tenant, since `{tenant}.{instance}.myworkdayjobs.com/{site}` cannot be derived from a company
    /// name — there is no rule that turns "Acme" into `acme.wd5`.
    public static func resolve(
        boardURL: String, session: URLSession = .shared
    ) async -> ResolutionResult {
        guard let identified = identify(boardURL: boardURL) else {
            return .failed(.unusableName(
                "that doesn't look like a Greenhouse, Lever, Ashby or Workday board address"
            ))
        }
        switch await probe(kind: identified.kind, slug: identified.slug, session: session) {
        case let .listing(count):
            return .resolved(ResolvedBoard(
                kind: identified.kind, displayName: identified.displayName, slug: identified.slug,
                boardURL: identified.boardURL, jobCount: count
            ))
        case .empty:
            return .failed(.boardsFoundButEmpty([identified]))
        case .absent:
            return .failed(.noBoardFound)
        case let .unknown(detail):
            return .failed(.inconclusive(detail))
        }
    }

    /// Which vendor a URL belongs to, and what config would reach it. Pure — no network.
    ///
    /// Accepts a posting deep link as readily as a board landing page, because that is at least as
    /// likely to be what the user has in their clipboard.
    public static func identify(boardURL: String) -> ResolvedBoard? {
        guard let url = URL(string: boardURL.trimmingCharacters(in: .whitespaces)),
              let host = url.host?.lowercased() else { return nil }
        let segments = url.path.split(separator: "/").map(String.init)

        // Workday keeps its whole config in the URL, so the slug IS the URL.
        if ATSHost.belongs(host, to: "myworkdayjobs.com"), let board = WorkdayJobBoard.board(for: url) {
            return ResolvedBoard(
                kind: "workday", displayName: "Workday", slug: boardURL,
                boardURL: "\(board.jobBase)", jobCount: 0,
                suggestedCompany: board.tenant
            )
        }
        // Everything else is `{host}/{slug}[/...]`.
        let kind: String? = if ATSHost.belongs(host, to: "greenhouse.io") {
            "greenhouse"
        } else if ATSHost.belongs(host, to: "ashbyhq.com") {
            "ashby"
        } else if ATSHost.belongs(host, to: "lever.co") {
            "lever"
        } else {
            nil
        }
        guard let kind, let slug = segments.first else { return nil }
        return candidate(kind: kind, slug: slug)
    }

    // MARK: - Re-resolution

    /// Look for a replacement board for a source that has gone quiet.
    ///
    /// Only ever *offers* — it returns a candidate and the caller decides. Silently repointing a
    /// source at a board that merely shares a name is how a user ends up tracking the wrong company
    /// without ever being told.
    ///
    /// The current board is re-probed first: three empty runs can also mean a company genuinely
    /// paused hiring, and moving them to a different vendor in that case would be wrong.
    public static func reresolve(
        currentKind: String,
        currentSlug: String,
        companyName: String,
        session: URLSession = .shared
    ) async -> ResolutionResult {
        if case let .listing(count) = await probe(
            kind: currentKind, slug: currentSlug, session: session
        ) {
            let existing = candidate(kind: currentKind, slug: currentSlug)
            return .resolved(ResolvedBoard(
                kind: currentKind,
                displayName: existing?.displayName ?? currentKind,
                slug: currentSlug,
                boardURL: existing?.boardURL ?? currentSlug,
                jobCount: count
            ))
        }
        return await resolve(companyName: companyName, session: session)
    }
}
