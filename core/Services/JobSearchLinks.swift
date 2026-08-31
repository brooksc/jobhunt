import Foundation

/// Builds the outbound "research this job elsewhere" URLs shown in the job detail pane, plus the
/// heuristic that decides when the "find on company site" search is unnecessary. Pure and testable —
/// no SwiftData / SwiftUI. The query shape and excluded aggregators are tunable (see docs/tuning.md).
public enum JobSearchLinks {
    // MARK: - Tunable constants (see docs/tuning.md)

    /// Aggregators to push *out* of the "find on company site" results — the whole point is to surface
    /// the company's own posting (or its ATS), not another job board. ATS domains (greenhouse/lever/
    /// workday/…) are intentionally NOT excluded: applying through a company's ATS is "direct."
    public static let excludedAggregatorDomains = [
        "linkedin.com", "indeed.com", "glassdoor.com", "ziprecruiter.com"
    ]

    /// Company-name tokens too generic to prove a URL is "the company's site" (would false-positive on
    /// unrelated domains). Used by `postingIsOnCompanySite`.
    static let genericCompanyTokens: Set<String> = [
        "inc", "llc", "corp", "co", "ltd", "plc", "the", "and", "group", "holdings", "holding",
        "technologies", "technology", "tech", "solutions", "services", "systems", "software",
        "labs", "lab", "ai", "global", "international", "worldwide", "ventures"
    ]

    // MARK: - Referral search (LinkedIn)

    /// LinkedIn company search for `company` — the entry point to finding first-degree connections who
    /// work there (a referral is the single biggest boost to getting an application seen). Returns nil
    /// when there's no company name to search.
    public static func linkedInConnectionsURL(company: String?) -> URL? {
        guard let company = nonEmpty(company) else { return nil }
        var components = URLComponents(string: "https://www.linkedin.com/search/results/companies/")
        components?.queryItems = [URLQueryItem(name: "keywords", value: company)]
        return components?.url
    }

    // MARK: - Official-posting search (Google)

    /// Google search biased toward the official posting on the company's own site/ATS: company + title,
    /// nudged with `(careers OR jobs)` and the aggregators excluded. Title is passed raw (real titles
    /// are long/parenthetical, so quoting them tanks results to zero). Returns nil unless both company
    /// and title are present.
    public static func companySiteSearchURL(company: String?, title: String?) -> URL? {
        guard let company = nonEmpty(company), let title = nonEmpty(title) else { return nil }
        let exclusions = excludedAggregatorDomains.map { "-site:\($0)" }.joined(separator: " ")
        let query = "\(company) \(title) (careers OR jobs) \(exclusions)"
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    // MARK: - "Already on the company's site?" heuristic

    /// The significant (non-generic, ≥3-char) tokens of a company name, used to test a URL for the
    /// company's identity.
    static func companyMatchTokens(_ company: String?) -> [String] {
        guard let company else { return [] }
        return company.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !genericCompanyTokens.contains($0) }
    }

    /// True when the posting URL appears to already be on the company's own site or ATS — i.e. a
    /// significant company-name token occurs anywhere in the URL (host OR path, so `google.com` and
    /// `greenhouse.io/gitlab` both match). When true, the "find on company site" search is redundant
    /// and the button is disabled. Deliberately loose (substring match) — the user accepts occasional
    /// false positives in exchange for one fewer pointless click.
    ///
    /// **Except on an aggregator, where the path match is actively wrong.** Aggregators put the
    /// company name in the URL slug, so a substring test over the whole URL says "already direct"
    /// about the one kind of link where the company's own posting is most worth finding. Jobs #966
    /// and #973 both hit this:
    ///
    ///     glassdoor.com/job-listing/staff-product-manager-ai-foundations-vanta-JV_KO0,36…
    ///     glassdoor.com/job-listing/sr-manager-technical-program-syniti-JV_KO0,28…
    ///
    /// Both disabled the button and told the user the posting "already looks like it's on Vanta's
    /// own site", while the host was Glassdoor. So the host is checked against the same
    /// `excludedAggregatorDomains` the Google query excludes — one list, used for both halves of the
    /// same judgement, rather than two that can disagree.
    public static func postingIsOnCompanySite(company: String?, postingURL: String?) -> Bool {
        guard let raw = nonEmpty(postingURL) else { return false }
        let url = raw.lowercased()
        // Host only, so an aggregator named in a *path* (a careers page linking out, say) still
        // reads as whatever site actually serves it.
        if let host = URL(string: raw)?.host?.lowercased(),
           excludedAggregatorDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return false
        }
        let tokens = companyMatchTokens(company)
        guard !tokens.isEmpty else { return false }
        return tokens.contains { url.contains($0) }
    }

    // MARK: - Helper

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
