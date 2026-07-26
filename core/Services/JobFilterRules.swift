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

    /// Whether a job matches the tri-state location-criteria filter: `wanted == nil` means "any",
    /// otherwise the job's stored verdict must equal it.
    ///
    /// A job whose verdict was never computed (`stored == nil` — e.g. extraction failed) matches
    /// neither "Meets" nor "Doesn't meet". Treating unknown as "doesn't meet" would quietly sweep
    /// un-extracted jobs into a review pile the user may act on, which is a different claim than the
    /// data supports.
    public static func matchesCriteria(stored: Bool?, wanted: Bool?) -> Bool {
        guard let wanted else { return true }
        return stored == wanted
    }
}
