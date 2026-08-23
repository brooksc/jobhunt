import Foundation

/// Why a swept posting didn't survive gate A. Surfaced as a histogram, because "0 new jobs" is
/// unactionable and "98% rejected on title" tells the user their keywords are wrong.
public enum DiscoveryRejectReason: String, Sendable, Equatable, CaseIterable {
    case title
    case location
    case salary
    case stale
}

public enum DiscoveryVerdict: Sendable, Equatable {
    case pass
    case reject(DiscoveryRejectReason)
}

/// Gate A: what a swept posting must clear before jobhunt spends anything on it (TASK-691, M2).
///
/// Runs on the raw board row — no network, no AI, no store access — so a 15,000-posting sweep costs
/// nothing but CPU. Modelled on `SavedSearchCriteria`: a `Sendable`, `Hashable` value decoupled
/// from SwiftData so matching runs off the main actor and is testable in isolation. `Hashable`
/// also earns its keep in the ledger, which stores the hash beside each verdict so a criteria
/// change re-evaluates the postings it already judged.
///
/// **This is a conservative pre-filter, not the requirement check.** `JobRequirements` remains the
/// authority and evaluates the fit floor, which cannot exist before extraction. Where the two could
/// disagree, this one passes: a false pass costs one extraction, a false reject is invisible and
/// permanent.
///
/// The matching rules below are ports, not inventions. Each is a fix the career-ops scanner made
/// after a silent miss in production, and the failure each one prevents is named in its comment —
/// they read as fussy until you know what happens without them.
///
/// Measured against that scanner's own history (400,616 postings swept, 141 added), the title
/// filter accounts for 96% of the reduction and location for the remaining 4%. Salary and content
/// filtering have never rejected a posting, so salary is evaluated but unexercised and a content
/// filter isn't built at all.
public struct DiscoveryCriteria: Sendable, Hashable {
    /// At least one must appear in the title. Empty means no title requirement — which, given the
    /// numbers above, means effectively no filter at all.
    public var titleIncludeAny: [String]
    /// Any match rejects. This is also how seniority is excluded ("Intern", "Junior"): a keyword
    /// the user can read and edit beats an inferred level they can't see.
    public var titleExcludeAny: [String]

    /// Location tiers, evaluated in this order. See `evaluate` for why there are four.
    public var locationBlockHard: [String]
    public var locationAlwaysAllow: [String]
    public var locationBlock: [String]
    /// Empty means any location passes.
    public var locationAllow: [String]

    /// Only applies when the vendor published a band. 0 disables.
    public var minSalaryIfPublished: Int
    public var maxSalaryIfPublished: Int
    /// 0 disables. A posting with no date always passes.
    public var maxAgeDays: Int

    public init(
        titleIncludeAny: [String] = [],
        titleExcludeAny: [String] = [],
        locationBlockHard: [String] = [],
        locationAlwaysAllow: [String] = [],
        locationBlock: [String] = [],
        locationAllow: [String] = [],
        minSalaryIfPublished: Int = 0,
        maxSalaryIfPublished: Int = 0,
        maxAgeDays: Int = 0
    ) {
        self.titleIncludeAny = titleIncludeAny
        self.titleExcludeAny = titleExcludeAny
        self.locationBlockHard = locationBlockHard
        self.locationAlwaysAllow = locationAlwaysAllow
        self.locationBlock = locationBlock
        self.locationAllow = locationAllow
        self.minSalaryIfPublished = minSalaryIfPublished
        self.maxSalaryIfPublished = maxSalaryIfPublished
        self.maxAgeDays = maxAgeDays
    }

    // MARK: - Evaluation

    public func evaluate(_ posting: DiscoveredPosting, now: Date = Date()) -> DiscoveryVerdict {
        if !passesTitle(posting.title) {
            return .reject(.title)
        }
        if !passesLocation(posting) {
            return .reject(.location)
        }
        if !passesSalary(posting) {
            return .reject(.salary)
        }
        if !passesAge(posting, now: now) {
            return .reject(.stale)
        }
        return .pass
    }

    func passesTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        if Self.anyMatches(titleExcludeAny, in: lower, boundaryAlways: false) {
            return false
        }
        if titleIncludeAny.isEmpty {
            return true
        }
        return Self.anyMatches(titleIncludeAny, in: lower, boundaryAlways: false)
    }

    /// Four tiers, in this order: `blockHard` → `alwaysAllow` → `block` → `allow`.
    ///
    /// The middle two look redundant until you meet a multi-location posting. `alwaysAllow` beats
    /// `block` so "Stockholm · London · Madrid" survives a London block entry — the role *is*
    /// available somewhere the user wants. But that unconditional win then discards a legitimate
    /// country-level block: an `alwaysAllow` entry for "Porto" rescues "Porto Alegre, Rio Grande do
    /// Sul, Brazil". `blockHard` is the one tier `alwaysAllow` cannot override, for entries that
    /// are country-level and therefore never a false rejection.
    ///
    /// Nothing to judge on → pass. That is the same "absent data never rejects" rule as everywhere
    /// else here, and it matters most for Workday, whose location is often a rollup count.
    func passesLocation(_ posting: DiscoveredPosting) -> Bool {
        let location = (posting.locationRaw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !location.isEmpty else { return true }

        if Self.anyMatches(locationBlockHard, in: location, boundaryAlways: true) {
            return false
        }
        if Self.anyMatches(locationAlwaysAllow, in: location, boundaryAlways: true) {
            return true
        }
        if Self.anyMatches(locationBlock, in: location, boundaryAlways: true) {
            return false
        }
        if locationAllow.isEmpty {
            return true
        }
        if Self.anyMatches(locationAllow, in: location, boundaryAlways: true) {
            return true
        }

        // Last resort, and deliberately AFTER `block` so a remote title can never rescue a blocked
        // location. Several ATSs report the hiring office as the location even when the role is
        // remote and say so only in the title; career-ops measured one tenant where 14 matching
        // postings all failed `allow` and 5 of them said "Remote" outright in the title. This
        // widens `allow`, never `block`.
        return Self.titleSignalsRemote(posting.title)
    }

    /// Range *overlap*, not a floor: reject only when the published band lies entirely outside the
    /// user's range. A posting whose band straddles the floor is a negotiation, not a mismatch.
    ///
    /// Currency mismatch rejects only when both sides are known — an unlabelled band is not
    /// evidence of a foreign currency.
    func passesSalary(_ posting: DiscoveredPosting) -> Bool {
        guard minSalaryIfPublished > 0 || maxSalaryIfPublished > 0 else { return true }
        let low = posting.salaryMinPublished ?? posting.salaryMaxPublished
        let high = posting.salaryMaxPublished ?? posting.salaryMinPublished
        guard let low, let high else { return true }

        if minSalaryIfPublished > 0, high < minSalaryIfPublished {
            return false
        }
        if maxSalaryIfPublished > 0, low > maxSalaryIfPublished {
            return false
        }
        return true
    }

    /// A posting with no date passes. Workday's "Posted 30+ Days Ago" bucket is unbounded and
    /// yields no date at all, so an age filter that rejected undated postings would silently
    /// discard most of a Workday tenant.
    func passesAge(_ posting: DiscoveredPosting, now: Date) -> Bool {
        guard maxAgeDays > 0, let published = posting.firstPublished else { return true }
        return published >= now.addingTimeInterval(-Double(maxAgeDays) * 86400)
    }

    // MARK: - Keyword matching

    /// Whether any keyword matches, with the boundary rule appropriate to the field.
    ///
    /// **Title keywords**: a 2–3 letter all-letter keyword is anchored on word boundaries;
    /// everything else is a plain substring. Without the anchor, "COO" matches *Coordinator* and
    /// "AI" matches *Maintenance* — a silent flood, and the sweep summary reports one "passed"
    /// count that can't distinguish a tuned filter from a leaking one. Longer keywords stay
    /// permissive on purpose, so "program manager" still matches "Senior Program Manager, Platform".
    ///
    /// **Location keywords**: *always* anchored. Country and city names are prefixes of unrelated
    /// places, and the motivating bug is worth remembering — blocking "india" also rejected
    /// *Indian Head, MD*, *Indiana* and *Indianapolis*, real US locations dropped from every scan
    /// with nothing on screen to say so. Same class: "china" swallows *Chinatown*.
    static func anyMatches(_ keywords: [String], in haystack: String, boundaryAlways: Bool) -> Bool {
        for keyword in keywords {
            let needle = keyword.trimmingCharacters(in: .whitespaces).lowercased()
            // An empty keyword would match everything via `contains("")`, silently disabling the
            // tier it belongs to.
            guard !needle.isEmpty else { continue }
            if boundaryAlways || isShortAcronym(needle) {
                if matchesOnBoundary(needle, in: haystack) {
                    return true
                }
            } else if haystack.contains(needle) {
                return true
            }
        }
        return false
    }

    static func isShortAcronym(_ keyword: String) -> Bool {
        keyword.count >= 2 && keyword.count <= 3 && keyword.allSatisfy { $0.isLetter && $0.isASCII }
    }

    /// Lookarounds rather than `\b`, so a keyword that begins or ends with punctuation (", IND",
    /// "UK -") still anchors correctly — `\b` is defined relative to word characters and behaves
    /// surprisingly at a punctuation edge.
    static func matchesOnBoundary(_ needle: String, in haystack: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: needle)
        let prefix = needle.first.map { $0.isLetter || $0.isNumber } == true ? "(?<![a-z0-9])" : ""
        let suffix = needle.last.map { $0.isLetter || $0.isNumber } == true ? "(?![a-z0-9])" : ""
        guard let regex = try? NSRegularExpression(pattern: prefix + escaped + suffix) else {
            return haystack.contains(needle)
        }
        let range = NSRange(haystack.startIndex ..< haystack.endIndex, in: haystack)
        return regex.firstMatch(in: haystack, range: range) != nil
    }

    // MARK: - Remote marker

    /// "Remote" must be followed by end-of-string, a non-letter (")", ",", "-") or " in …" as in
    /// "Remote in MO" — never by another word. A bare search for the word admits the domain
    /// compounds: "Remote Sensing Program Manager" is an on-site GIS role, and companies do post
    /// exactly those.
    static let remoteMarker = #"(?<![a-z])remote(?=$|\s*[^a-z\s]|\s+in\b)"#

    /// A negation before the word has to lose, which the marker alone can't see: in "Non-Remote"
    /// the delimiter clears the lookbehind and the trailing position clears the lookahead, so an
    /// explicitly on-site role would bypass a non-empty `allow` list — the exact opposite of the
    /// intent.
    ///
    /// `[^a-z]*` rather than `[\s-]*` because an ASCII-only separator lets every non-ASCII dash
    /// through: "Non–Remote" (en dash), "Non‑Remote" (non-breaking hyphen), em dash and minus all
    /// still read as remote. It can't over-reach, because it never crosses a letter — in "Nonprofit
    /// Program Manager - Remote" the run after "non" starts with "profit", so the negation can't
    /// reach the marker.
    static let remoteNegation = #"\b(?:non|not|no)[^a-z]*remote"#

    static func titleSignalsRemote(_ title: String) -> Bool {
        let lower = title.lowercased()
        guard !lower.isEmpty else { return false }
        // Over-rejecting is the safe direction here: this tier only ever *rescues* a posting, so a
        // false negative restores the previous behaviour while a false positive admits an on-site
        // role the user said they didn't want.
        if lower.range(of: remoteNegation, options: .regularExpression) != nil {
            return false
        }
        return lower.range(of: remoteMarker, options: .regularExpression) != nil
    }
}
