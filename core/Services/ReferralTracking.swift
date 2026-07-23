import Foundation

// MARK: - Referral tracking (TASK-630)

/// Per-attempt outcome. `notPursuing` is a job-level decision recorded as a recipient-less marker.
public enum ReferralOutcome: String, Sendable, CaseIterable {
    case requested
    case referred
    case declined
    case notPursuing = "not_pursuing"
}

/// The derived per-job referral summary — orthogonal to `JobStatus` (AC #1/#3).
public enum ReferralSummary: String, Sendable, CaseIterable {
    case none // no outreach applies (not in the active funnel, no attempts)
    case needsOutreach = "needs_outreach"
    case requested
    case referred
    case declined
    case notPursuing = "not_pursuing"

    public var label: String {
        switch self {
        case .none: "—"
        case .needsOutreach: "Needs outreach"
        case .requested: "Requested"
        case .referred: "Referred"
        case .declined: "Declined"
        case .notPursuing: "Not pursuing"
        }
    }

    /// Whether this summary represents an outstanding action (drives the "needs outreach" filter/count).
    public var needsAction: Bool { self == .needsOutreach }
}

public enum ReferralTracking {
    /// Statuses in the active application funnel where a missing referral reads as "Needs outreach"
    /// (AC #2). Jobs outside it don't get a misleading action requirement.
    public static let funnelStatuses: Set<String> = ["applied", "interview", "offer"]

    /// Minimal projection of a referral attempt for the pure derivation (SwiftData-free, testable).
    public struct Attempt: Sendable, Equatable {
        public let outcome: ReferralOutcome
        public let recipientName: String
        public let recipientIdentifier: String?
        public let requestedAt: Date
        public init(outcome: ReferralOutcome, recipientName: String, recipientIdentifier: String?, requestedAt: Date) {
            self.outcome = outcome
            self.recipientName = recipientName
            self.recipientIdentifier = recipientIdentifier
            self.requestedAt = requestedAt
        }
    }

    /// Derive the job's referral summary from its status + attempts (AC #2/#3/#16). Real attempts (any
    /// recipient outreach) take precedence over the `notPursuing` marker; a job leaving the funnel
    /// (archived/closed/etc.) keeps recorded attempts but is no longer "Needs outreach".
    public static func summary(jobStatus: String, attempts: [Attempt]) -> ReferralSummary {
        let real = attempts.filter { $0.outcome != .notPursuing }
        if real.contains(where: { $0.outcome == .referred }) { return .referred }
        if real.contains(where: { $0.outcome == .requested }) { return .requested }
        if !real.isEmpty { return .declined } // real attempts exist but none requested/referred → all declined
        if attempts.contains(where: { $0.outcome == .notPursuing }) { return .notPursuing }
        return funnelStatuses.contains(jobStatus) ? .needsOutreach : .none
    }

    // MARK: - Duplicate-recipient detection (AC #6)

    /// A normalized key for a recipient: the identifier (LinkedIn URL / email, lowercased, trimmed) when
    /// present, else the normalized name. Empty when neither is usable.
    public static func recipientKey(name: String?, identifier: String?) -> String {
        let id = (identifier ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return id }
        return (name ?? "")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The first prior real attempt whose recipient matches `name`/`identifier` (AC #6) — so the UI can
    /// warn (with its date) before recording another outreach to the same person. `notPursuing` markers
    /// and empty keys never match.
    public static func duplicateAttempt(name: String?, identifier: String?, among attempts: [Attempt]) -> Attempt? {
        let key = recipientKey(name: name, identifier: identifier)
        guard !key.isEmpty else { return nil }
        return attempts.first { attempt in
            attempt.outcome != .notPursuing
                && recipientKey(name: attempt.recipientName, identifier: attempt.recipientIdentifier) == key
        }
    }
}
