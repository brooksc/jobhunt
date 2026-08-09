import Foundation

/// A canonical seniority band.
///
/// `Job.seniority` was free text: 55 distinct values across 415 jobs, including pure case duplicates
/// (`Senior` 134 / `senior` 42), five spellings of mid-level, and strings carrying no level at all
/// ("5+ years", "III"). That text is injected into the fit-scoring prompt under `experience_level`,
/// so the inconsistency was feeding the scorer, not merely blocking a future filter.
///
/// Both tracks are represented because postings use both, and collapsing `Director` into `Principal`
/// would lose the distinction the user is actually triaging on.
public enum SeniorityLevel: String, CaseIterable, Sendable {
    case intern
    case entry
    case mid
    case senior
    case lead
    case staff
    case principal
    case manager
    case director
    case executive

    /// For the prompt's enum constraint, in ascending order.
    public static var promptList: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}

/// Maps whatever a posting said onto `SeniorityLevel`, or to nil when it said nothing usable.
public enum SeniorityNormalizer {
    /// Returns the canonical raw value, or nil when the input carries no reliable level signal.
    ///
    /// **Nil rather than a guess** is deliberate for two families the live data is full of:
    /// bare experience ranges ("5+ years", "10–15+ years") and bare ordinals ("II", "III"). Years
    /// map to wildly different bands by industry and company, and an ordinal has no scale attached —
    /// inventing a band from either would push a fabricated signal into `experience_level` scoring,
    /// which is worse than the honest absence the scorer already handles.
    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // "Senior/Principal", "Staff / Senior" — take the FIRST named level. A range's lower bound is
        // the level the posting will actually consider, and overstating it would inflate the fit of
        // roles the candidate is under-levelled for.
        if let separator = text.firstIndex(where: { $0 == "/" || $0 == "|" }) {
            text = String(text[text.startIndex ..< separator])
        }
        text = text.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Anything that is only digits, ordinals or a years phrase carries no band.
        if text.range(of: "^(i{1,3}|iv|v|[0-9]+)$", options: .regularExpression) != nil { return nil }
        if text.contains("year") || text.range(of: "^[0-9]", options: .regularExpression) != nil {
            return nil
        }

        // Longest-match first: "senior manager" must not be caught by the "senior" rule, and
        // "mid senior" must not be caught by "senior".
        let rules: [(needles: [String], level: SeniorityLevel)] = [
            (["intern", "internship", "co op", "coop"], .intern),
            (["new grad", "new graduate", "graduate", "entry", "junior", "jr", "associate"], .entry),
            (["mid senior", "midsenior", "mid level", "midlevel", "mid", "intermediate", "experienced"], .mid),
            (["senior manager", "sr manager"], .manager),
            (["senior director", "sr director"], .director),
            (["senior", "sr"], .senior),
            (["tech lead", "team lead", "lead"], .lead),
            (["staff"], .staff),
            (["principal", "distinguished", "fellow"], .principal),
            (["manager", "mgr"], .manager),
            (["director", "head of"], .director),
            (["vp", "avp", "svp", "evp", "vice president", "chief", "cto", "ceo", "executive"], .executive)
        ]

        for rule in rules where rule.needles.contains(where: { matchesWord($0, in: text) }) {
            return rule.level.rawValue
        }
        // An exact enum name that somehow escaped the rules above.
        return SeniorityLevel(rawValue: text)?.rawValue
    }

    /// Whole-word match, so "senior" doesn't fire on "seniority" and "vp" doesn't fire on "vpn".
    private static func matchesWord(_ needle: String, in text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        let needleWords = needle.split(separator: " ").map(String.init)
        guard needleWords.count > 1 else { return words.contains(needle) }
        guard words.count >= needleWords.count else { return false }
        for start in 0 ... (words.count - needleWords.count)
            where Array(words[start ..< start + needleWords.count]) == needleWords {
            return true
        }
        return false
    }
}
