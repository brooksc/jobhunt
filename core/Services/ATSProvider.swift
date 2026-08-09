import Foundation

/// A posting as the employer's ATS publishes it, normalized across vendors (TASK-636).
///
/// Every field except `providerName` and `boardKey` is optional because the vendors disagree about
/// what they publish: Ashby has no `updatedAt`, Lever has no update timestamp at all, Greenhouse has
/// both. Modelling the union and letting callers cope is more honest than inventing values.
public struct ATSPosting: Sendable, Equatable {
    /// The description as plain text, already unescaped and stripped.
    public let contentPlain: String
    public let title: String?
    public let locationName: String?
    public let firstPublished: Date?
    public let updatedAt: Date?
    public let absoluteURL: String?
    /// Which vendor answered, for messages the user reads ("Refreshed from Ashby").
    public let providerName: String
    /// The vendor-specific board identifier that answered — a Greenhouse board slug, a Lever or
    /// Ashby company handle. Worth carrying because for Greenhouse it's a *guess*.
    public let boardKey: String

    public init(
        contentPlain: String,
        title: String?,
        locationName: String?,
        firstPublished: Date?,
        updatedAt: Date?,
        absoluteURL: String?,
        providerName: String,
        boardKey: String
    ) {
        self.contentPlain = contentPlain
        self.title = title
        self.locationName = locationName
        self.firstPublished = firstPublished
        self.updatedAt = updatedAt
        self.absoluteURL = absoluteURL
        self.providerName = providerName
        self.boardKey = boardKey
    }
}

/// An authoritative, public, no-credential source for a posting.
///
/// The point of the abstraction is that description-refresh, freshness, company-roles and
/// form-preview stop being Greenhouse-only features. Each implementation is best-effort: `nil` and
/// `[]` mean "couldn't tell", never "definitely not", so callers fall back to the captured HTML
/// rather than acting on an absence.
public protocol ATSProvider: Sendable {
    /// Shown to the user, so it should be the vendor's own name.
    var name: String { get }

    /// Whether this provider handles an ATS id from `DuplicateDetector.atsPostingID`
    /// (e.g. `gh:123`, `lever:spotify:uuid`).
    func handles(atsID: String) -> Bool

    /// The canonical posting, or nil when it can't be resolved.
    func fetchPosting(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> ATSPosting?

    /// Every other open role on the same board. Empty when unsupported or unreachable.
    func listOpenRoles(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> [GreenhouseJobBoard.OpenRole]

    /// Whether the posting is still listed: `true` alive, `false` removed, `nil` couldn't tell.
    ///
    /// `nil` and `false` must stay distinct. Treating "couldn't reach the board" as "removed" would
    /// mass-expire live jobs on any transient outage — the exact failure the Greenhouse
    /// implementation guards against by confirming the board itself resolves first.
    func isAlive(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> Bool?

    /// The application form, when the vendor publishes it. Only Greenhouse does today.
    func fetchApplicationForm(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> ApplicationFormPreview?
}

public extension ATSProvider {
    /// A provider that can fetch the posting can answer liveness by whether it found it. Providers
    /// whose "not found" is unreliable — or that can't fetch content at all — override this.
    func isAlive(
        atsID: String, company: String?, urlString: String, session: URLSession
    ) async -> Bool? {
        await fetchPosting(
            atsID: atsID, company: company, urlString: urlString, session: session
        ) == nil ? nil : true
    }

    /// Most vendors publish no form; overriding is opt-in rather than boilerplate per provider.
    func fetchApplicationForm(
        atsID _: String, company _: String?, urlString _: String, session _: URLSession
    ) async -> ApplicationFormPreview? {
        nil
    }
}

/// Chooses a provider for a job's ATS id (TASK-636).
public enum ATSRegistry {
    public static let providers: [any ATSProvider] = [
        GreenhouseProvider(),
        LeverProvider(),
        AshbyProvider(),
        WorkdayProvider()
    ]

    /// The provider for this id, or nil when the posting is on a source we can't query
    /// authoritatively (LinkedIn, a bespoke career site). Those keep today's HTML-based behaviour.
    public static func provider(forATSID atsID: String) -> (any ATSProvider)? {
        providers.first { $0.handles(atsID: atsID) }
    }

    /// The first ATS id found across a job's URLs, with its provider.
    public static func resolve(urls: [String?]) -> (atsID: String, provider: any ATSProvider)? {
        for case let urlString? in urls {
            guard let atsID = DuplicateDetector.atsPostingID(urlString: urlString),
                  let provider = provider(forATSID: atsID) else { continue }
            return (atsID, provider)
        }
        return nil
    }
}
