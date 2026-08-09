import Foundation

/// Reads a posting from Greenhouse's public Job Board API (TASK-632).
///
/// For a job carrying a `gh_jid`, the API returns the posting the employer actually published —
/// full description, title, location, departments — where the capture is whatever the career site's
/// JavaScript shell happened to render. Nebius (#341) serves a 754 KB shell with no description in
/// it at all while the API has the complete text.
///
/// No key, no auth. The board slug is a guess derived from the URL and company name
/// (`AvailabilityChecker.greenhouseBoardCandidates`), which is why every failure here is soft: a
/// wrong guess must degrade to "couldn't refresh", never to overwriting a good capture with an
/// error page.
public enum GreenhouseJobBoard {
    public struct Posting: Sendable, Equatable {
        /// `content` from the API: HTML, and HTML-*escaped* on top of that.
        public let contentHTML: String
        public let title: String?
        public let locationName: String?
        public let departments: [String]
        public let updatedAt: Date?
        /// When the posting first went up. Distinct from `updatedAt`, which moves on any edit —
        /// see `PostingFreshness` for why the difference matters (TASK-633).
        public let firstPublished: Date?
        public let absoluteURL: String?
        /// Which board slug answered — worth surfacing, since it's a guess.
        public let board: String
    }

    public enum RefreshError: Error, Equatable {
        /// No `gh_jid` in any of the job's URLs — this posting isn't Greenhouse-backed.
        case notGreenhouse
        /// Every candidate board slug failed to return the posting.
        case boardNotResolved
        /// The board answered but the payload wasn't what we expect.
        case malformedResponse
    }

    /// Tries each candidate board until one returns the posting.
    ///
    /// - Parameter session: pass an ephemeral session from callers that fan out; `URLSession.shared`
    ///   pools connections and that pooling has already caused cross-test `-1005` failures here.
    public static func fetch(
        ghjid: String,
        company: String?,
        urlString: String,
        session: URLSession = .shared
    ) async -> Result<Posting, RefreshError> {
        let candidates = AvailabilityChecker
            .greenhouseBoardCandidates(company: company, urlString: urlString)
            .prefix(4)
        guard !candidates.isEmpty else { return .failure(.boardNotResolved) }

        var sawMalformed = false
        for board in candidates {
            guard let url = URL(
                string: "https://boards-api.greenhouse.io/v1/boards/\(board)/jobs/\(ghjid)"
            ) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

            if let posting = decode(data, board: board) { return .success(posting) }
            // A 200 that won't decode is a different failure from a 404, and reporting it as "board
            // not resolved" would send someone looking for the wrong problem.
            sawMalformed = true
        }
        return .failure(sawMalformed ? .malformedResponse : .boardNotResolved)
    }

    /// Split out from `fetch` so the payload shape is testable without a network round trip.
    public static func decode(_ data: Data, board: String) -> Posting? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // `content` is the only field worth failing over — the rest are enrichment, and a posting
        // with a title but no body gives the refresh nothing to do.
        guard let content = raw["content"] as? String, !content.isEmpty else { return nil }

        let departments = (raw["departments"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String } ?? []

        return Posting(
            contentHTML: content,
            title: (raw["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            locationName: (raw["location"] as? [String: Any])?["name"] as? String,
            departments: departments,
            updatedAt: (raw["updated_at"] as? String).flatMap(parseTimestamp),
            firstPublished: (raw["first_published"] as? String).flatMap(parseTimestamp),
            absoluteURL: raw["absolute_url"] as? String,
            board: board
        )
    }

    /// Greenhouse stamps `updated_at` as ISO-8601, sometimes with fractional seconds.
    static func parseTimestamp(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    /// The posting's description as plain text, through the same cleaner the capture path uses.
    ///
    /// Running it through `cleanDescription` rather than a bespoke strip is the point: the API's
    /// `content` is escaped HTML, and the cleaner already handles unescaping, tag stripping and
    /// site-chrome removal. A second implementation would drift from what extraction was tuned on.
    /// Two passes, not one: `content` is HTML that has *also* been HTML-escaped, so a single strip
    /// only unescapes it and leaves literal `<p>` tags in the text handed to the model. The first
    /// pass decodes the entities into real markup; `cleanDescription` then strips it as usual.
    public static func plainTextDescription(_ posting: Posting) -> String {
        cleanDescription(visibleText: stripHtml(posting.contentHTML))
    }
}
