import Foundation

// MARK: - JobFilterRules (TASK-649)

/// Pure predicates for the Jobs list filters that have non-obvious semantics, kept in JobhuntCore so
/// they're unit-testable — the app's filter closure can't be reached from the test targets.
public enum JobFilterRules {
    /// Whether a job's remote type matches the selected set. A **missing** remote type counts as
    /// `.unknown`: that's the same bucket the Unknown toggle selects, and what `LocationCriteria`
    /// already treats as onsite. Before this, a nil remote type matched nothing, so the ~40 jobs with
    /// no stored value were unreachable by any filter.
    public static func matchesRemote(_ remoteType: RemoteType?, selected: Set<RemoteType>?) -> Bool {
        guard let selected else { return true } // nil = no filter
        return selected.contains(remoteType ?? .unknown)
    }

    /// How a job reads against the configured location/remote criteria.
    ///
    /// The stored `meetsCriteria` is a Bool, which collapses two very different failures: a posting
    /// that *states* an arrangement you disallow, and one that says nothing at all. `LocationCriteria`
    /// scores an unknown/absent remote type as onsite, so silent postings are stored as `false` —
    /// which reads as "rejected" when the truth is "unknown". Splitting them here needs no schema
    /// change or re-extraction, because the distinction is already in `remoteType`.
    public enum CriteriaBucket: String, CaseIterable, Sendable {
        /// Passes the configured criteria.
        case meets
        /// Fails only because the posting never stated an arrangement — worth a look, not a verdict.
        case notStated
        /// Fails on a stated arrangement/location the user disallows.
        case doesNotMeet
    }

    /// Classify a job. Returns nil when the verdict was never computed (extraction failed), so those
    /// jobs match no bucket rather than being lumped in with rejects.
    public static func criteriaBucket(meetsCriteria: Bool?, remoteType: RemoteType?) -> CriteriaBucket? {
        guard let meetsCriteria else { return nil }
        if meetsCriteria { return .meets }
        return switch remoteType {
        case .unknown, .none: .notStated
        case .remote, .hybrid, .onsite: .doesNotMeet
        }
    }

    /// Whether a job matches the selected bucket (`wanted == nil` means "any").
    public static func matchesCriteria(
        meetsCriteria: Bool?, remoteType: RemoteType?, wanted: CriteriaBucket?
    ) -> Bool {
        guard let wanted else { return true }
        return criteriaBucket(meetsCriteria: meetsCriteria, remoteType: remoteType) == wanted
    }

    /// Data-quality filter for triaging records worth repairing.
    public enum QualityFilter: String, CaseIterable, Sendable {
        /// Any `QualityChecker` issue at all.
        case hasIssues
        /// Only jobs carrying a high-severity issue (missing company/title/location, or a failed
        /// extraction) — the ones actually worth re-sourcing from the company's own posting.
        case highSeverity

        public var label: String {
            switch self {
            case .hasIssues: "Any issue"
            case .highSeverity: "High severity"
            }
        }
    }

    /// Whether a job's capture host is in the selected set (`selected == nil` means "any source").
    ///
    /// Source matters because aggregators and ATS boards need different handling: a LinkedIn record
    /// usually has to be re-found on the company's own posting, while a Greenhouse/Ashby URL already
    /// *is* the canonical one. Previously the host was only reachable through `displayCompany`'s
    /// fallback, i.e. solely for jobs whose company failed to extract.
    public static func matchesSource(host: String?, selected: Set<String>?) -> Bool {
        guard let selected else { return true }
        guard let host else { return false } // no capture/host → not from any named source
        return selected.contains(host)
    }

    /// Fit-score filter. `unscoredOnly` selects jobs that were never scored — unreachable via
    /// `minimum`, because an absent score compares as 0 and is excluded by every threshold (the same
    /// nil-is-unreachable trap as remote type and the criteria verdict).
    public static func matchesFitScore(fitScore: Int?, minimum: Int?, unscoredOnly: Bool) -> Bool {
        if unscoredOnly { return fitScore == nil }
        guard let minimum else { return true }
        return (fitScore ?? 0) >= minimum
    }

    /// Whether a job's quality issues match the filter (`wanted == nil` means "any job").
    ///
    /// Callers should only evaluate `QualityChecker.issues(for:)` when a quality filter is active:
    /// computing it faults each job's `Capture` when the byte-count caches are absent, which is the
    /// per-keystroke cost TASK-610 removed from the search path.
    public static func matchesQuality(kinds: [QualityIssueKind], wanted: QualityFilter?) -> Bool {
        switch wanted {
        case .none: true
        case .hasIssues: !kinds.isEmpty
        case .highSeverity: kinds.contains(where: \.isHighSeverity)
        }
    }
}
