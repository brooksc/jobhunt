import Foundation

/// One row from a board sweep, before any AI and before any per-posting fetch (TASK-691, M2).
///
/// Deliberately the *raw* vendor shape. Nothing here is inferred, parsed into an app enum, or
/// enriched — `locationRaw` is the vendor's own string, not a `RemoteType`, because gate A
/// (`DiscoveryCriteria`) has to run before anything expensive happens and cannot afford to be
/// wrong in a way that looks like a considered judgement.
///
/// Most fields are optional because vendors disagree about what they publish at list time. Only
/// Ashby and Lever include a description; nobody except Ashby publishes a salary band; Workday has
/// no absolute date. `DiscoveryCriteria` is built around that: an absent field is never a
/// rejection, so a criterion simply doesn't apply to a vendor that omits its input.
public struct DiscoveredPosting: Sendable, Equatable {
    /// Stable identity for cross-run dedup. `DuplicateDetector.atsPostingID` where the URL is
    /// recognisably an ATS posting, else a normalised URL — see `dedupKey(for:)`.
    public let dedupKey: String
    public let url: String
    public let title: String
    public let company: String?
    /// The vendor's own location string, exactly as published.
    public let locationRaw: String?
    public let firstPublished: Date?
    /// Only when the vendor publishes a band. Absent is "unknown", never "doesn't pay enough".
    public let salaryMinPublished: Int?
    public let salaryMaxPublished: Int?
    public let salaryCurrency: String?
    /// Present only when the *list* payload carried it for free. A sweep must never issue a
    /// request per posting to fill this in — that's what hydration is for, and it runs after the
    /// gate on survivors only.
    public let descriptionPlain: String?
    /// Which `SearchSource` produced this row.
    public let sourceID: String

    public init(
        dedupKey: String,
        url: String,
        title: String,
        company: String? = nil,
        locationRaw: String? = nil,
        firstPublished: Date? = nil,
        salaryMinPublished: Int? = nil,
        salaryMaxPublished: Int? = nil,
        salaryCurrency: String? = nil,
        descriptionPlain: String? = nil,
        sourceID: String = ""
    ) {
        self.dedupKey = dedupKey
        self.url = url
        self.title = title
        self.company = company
        self.locationRaw = locationRaw
        self.firstPublished = firstPublished
        self.salaryMinPublished = salaryMinPublished
        self.salaryMaxPublished = salaryMaxPublished
        self.salaryCurrency = salaryCurrency
        self.descriptionPlain = descriptionPlain
        self.sourceID = sourceID
    }

    /// The ledger key for a posting URL.
    ///
    /// `DuplicateDetector.atsPostingID` is preferred because it survives the URL cosmetics that
    /// differ between a board listing and a browser capture of the same posting — the same reason
    /// ingest already keys on it. It returns nil for anything it doesn't recognise (a market-wide
    /// aggregator, a company's own careers page), and those still need a key, so a normalised URL
    /// is the fallback.
    ///
    /// The prefix keeps the two namespaces apart: an ATS id and a URL that happened to spell the
    /// same characters must not collide.
    public static func dedupKey(for urlString: String) -> String? {
        if let atsID = DuplicateDetector.atsPostingID(urlString: urlString) {
            return atsID
        }
        guard let normalized = URLNormalizer.normalized(urlString) else { return nil }
        return "url:\(normalized)"
    }
}
