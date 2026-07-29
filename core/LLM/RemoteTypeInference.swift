import Foundation

/// Fills in a missing work arrangement from the location text.
///
/// Extraction sometimes returns a location that plainly states the arrangement ("United States -
/// Remote") while leaving `remote_type` null. The job then reads as "Arrangement not stated", matches
/// the *Unknown* filter instead of *Remote*, and — because a null arrangement falls to the on-site
/// branch — gets judged as failing the location criteria. Job #525 (The Hartford) hit all three.
///
/// It never overrides an arrangement the extractor actually determined — it only fills a missing one.
///
/// Beyond that it is deliberately *permissive*: any mention of remote counts, including postings that
/// offer a choice ("Remote, hybrid, or in-office (Columbus, OH)"). That trade is chosen on purpose.
/// A false positive surfaces a hybrid role in the Remote filter and costs one archive click; a false
/// negative leaves a genuinely remote job filed under "Unknown", where a remote-only search never
/// looks. The second error is the expensive one, so ambiguity resolves toward remote.
///
/// Negations are still excluded — "not remote" isn't ambiguous, it's the opposite claim.
public enum RemoteTypeInference {
    /// Phrasings where "remote" appears but is being denied.
    private static let negations = ["not remote", "no remote", "non remote", "not a remote"]

    public static func infer(remoteType: RemoteType?, location: String?) -> RemoteType? {
        // Never second-guess an arrangement the extractor actually determined.
        guard remoteType == nil || remoteType == .unknown else { return remoteType }

        // Normalized so "on-site"/"On Site" and "US-CA-Remote" both tokenize predictably.
        let text = normalizeForMatch(location ?? "")
        guard text.contains("remote") else { return remoteType }
        guard !negations.contains(where: { text.contains($0) }) else { return remoteType }
        return .remote
    }
}
