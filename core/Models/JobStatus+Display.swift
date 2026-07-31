import Foundation

// MARK: - Status display vocabulary

public extension JobStatus {
    /// The user-facing name. Deliberately decoupled from `rawValue`: `pursuing` reads as "Interested"
    /// while the stored value stays `"pursuing"`, because raw values must keep matching the legacy
    /// SQLite strings for CSV / MCP / extension parity (and `DashboardMetrics.statusTarget` parses
    /// them out of timeline notes). Never render `rawValue` directly in the UI.
    var displayName: String {
        switch self {
        case .new: "New"
        case .pursuing: "Interested"
        case .applied: "Applied"
        case .interview: "Interview"
        case .offer: "Offer"
        case .rejected: "Rejected"
        case .passed: "Passed"
        case .archived: "Archived"
        case .closed: "Closed"
        case .duplicate: "Duplicate"
        case .expired: "Expired"
        }
    }
}

public enum StatusDisplay {
    /// Map a stored status token to its user-facing name, leaving anything unrecognised untouched.
    public static func label(forRawValue raw: String) -> String {
        JobStatus(rawValue: raw.lowercased())?.displayName ?? raw
    }

    /// Rewrite the status tokens inside a stored timeline note for display only.
    ///
    /// Notes are persisted verbatim as `"Status changed from new to pursuing"` and are *parsed* by
    /// `DashboardMetrics.statusTarget(fromNote:)`, which expects the raw token — so the stored text
    /// must not change. Only the rendering is translated, which is why this exists rather than a data
    /// migration: rewriting history would break both recap categorisation and the legacy-word mapping.
    public static func humanizedNote(_ note: String) -> String {
        // Only the machine-written status notes are rewritten. Translating any note would corrupt the
        // user's own prose — a note containing "new" or "applied" as ordinary words would get those
        // words capitalized mid-sentence.
        let lowered = note.lowercased()
        guard lowered.hasPrefix("status changed") || lowered.hasPrefix("restored to") else { return note }

        var out = note
        // Rewrite ONLY the token in a transition position ("from X", "to Y"). Matching bare tokens
        // anywhere would also capitalize incidental words — "un-marked a heuristic duplicate flag"
        // became "… a heuristic Duplicate flag", because `duplicate` is itself a status name.
        // Longest raw value first, so a token can't be partly consumed by a shorter overlapping one.
        for status in JobStatus.allCases.sorted(by: { $0.rawValue.count > $1.rawValue.count }) {
            out = out.replacingOccurrences(
                of: "\\b(from|to) \(NSRegularExpression.escapedPattern(for: status.rawValue))\\b",
                with: "$1 \(status.displayName)",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return out
    }
}

// MARK: - Location criteria display

public extension JobFilterRules.CriteriaBucket {
    /// The badge/filter wording. Shared so the job detail and the Jobs filter can't describe the same
    /// job differently — a posting that simply never stated its arrangement was previously labelled
    /// "Outside criteria" in the detail while the filter classified it as "Not stated", so it appeared
    /// rejected in one place and was absent from the matching filter in the other.
    var label: String {
        switch self {
        case .meets: "Meets criteria"
        // Generic: the bucket covers a missing salary or an unscored job too, not just a
        // missing work arrangement. The specific cause rides on the badge alongside it.
        case .notStated: "Not stated"
        case .doesNotMeet: "Outside criteria"
        }
    }
}
