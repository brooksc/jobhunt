import Foundation

/// Whether a page's `<link rel="canonical">` can be trusted to identify the *posting* that was
/// captured.
///
/// Ingestion treats a matching canonical URL as proof that two captures are the same posting, and
/// rewrites the existing capture in place. That is only safe if the canonical actually identifies the
/// job. Single-page job boards routinely break that assumption: Microsoft's board renders the posting
/// in a detail pane while the address bar carries `?pid=<posting id>`, but every job on the page emits
/// the *same* canonical pointing at the search results
/// (`…/careers?query=Technical%20Program%20Manager&location=&start=0`).
///
/// The consequence was silent data loss, not just a bad dedupe: capturing a second Microsoft job found
/// the first by canonical URL and overwrote its capture, so the new job never appeared and the old
/// one's content was replaced (job #2 was overwritten four times in one session).
///
/// The rule is one-directional on purpose. When the captured URL carries a posting identifier and the
/// canonical doesn't mention it, the canonical is describing something broader — a search page, a
/// board index — so it's dropped. Dropping a canonical only costs a missed cross-URL match, which
/// creates a separate job the user can merge; trusting a bad one destroys data.
public enum CanonicalURLPolicy {
    /// Query parameters whose value identifies a specific posting on a board.
    private static let postingIDParams: Set<String> = [
        "pid", "jid", "id", "jobid", "job_id", "jobpostingid", "postingid", "posting_id",
        "requisitionid", "requisition_id", "reqid", "gh_jid", "ashby_jid", "currentjobid", "lever_jid"
    ]

    /// The posting identifier carried in the URL's query string, if any.
    static func postingID(inQueryOf urlString: String) -> String? {
        guard let items = URLComponents(string: urlString)?.queryItems else { return nil }
        for item in items where postingIDParams.contains(item.name.lowercased()) {
            if let value = item.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Whether `canonical` can stand in as an identity for the posting captured at `captureURL`.
    ///
    /// A canonical on a different host is still allowed: an embedded board legitimately canonicalizes
    /// `company.com/careers?gh_jid=123` to `boards.greenhouse.io/company/jobs/123`, and the id check
    /// below is what keeps that honest.
    public static func identifiesSamePosting(canonical: String, captureURL: String) -> Bool {
        guard let id = postingID(inQueryOf: captureURL) else {
            // No identifier to check against — nothing suggests the canonical is broader.
            return true
        }
        // The id may appear in the canonical's path (`/jobs/123`) or its query (`?pid=123`), so match
        // against the whole string rather than assuming a shape.
        return canonical.localizedCaseInsensitiveContains(id)
    }

    /// The canonical URL to store: the input when it identifies the posting, otherwise nil.
    public static func trustworthyCanonical(_ canonical: String?, captureURL: String) -> String? {
        guard let canonical, !canonical.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return identifiesSamePosting(canonical: canonical, captureURL: captureURL) ? canonical : nil
    }
}
