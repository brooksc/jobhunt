import Foundation

/// What a check concluded about one posting (TASK-674).
///
/// Persisted per job so runs can be compared. The distinction that matters is the third case: a
/// posting we could not reach is **not** evidence that it is live, and conflating those two is what
/// let a run that checked nothing report an all-clear.
public enum AvailabilityVerdict: String, Sendable, CaseIterable {
    /// The posting answered, and it is still listed.
    case alive
    /// The posting answered, and it is gone.
    case gone
    /// No usable answer — rate-limited, bot-challenged, unreachable, or outside this run's window.
    case unverified

    public var label: String {
        switch self {
        case .alive: "Still listed"
        case .gone: "No longer listed"
        case .unverified: "Couldn't be checked"
        }
    }
}

/// One job's outcome from a run, flat enough to cross an actor boundary on its way to the store.
public struct AvailabilityOutcome: Sendable, Equatable {
    public let jobID: String
    public let verdict: AvailabilityVerdict
    /// The gone reason or the unverified reason — what makes the verdict judgeable after the fact.
    public let detail: String?

    public init(jobID: String, verdict: AvailabilityVerdict, detail: String?) {
        self.jobID = jobID
        self.verdict = verdict
        self.detail = detail
    }
}
