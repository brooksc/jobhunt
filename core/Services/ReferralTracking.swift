import Foundation

// MARK: - Referral tracking (TASK-630)

/// Per-request lifecycle state. A single referral request progresses `requested` → `responded`
/// (they agreed, no evidence yet) → `submitted` (confirmed in the company's system), or ends in
/// `declined`. `notApplicable` is a job-level "N/A — no referral possible / not pursuing" marker,
/// recorded as a recipient-less attempt (TASK-644).
///
/// Raw values are kept backward-compatible with the original TASK-630 data: `submitted` persists as
/// `"referred"` and `notApplicable` as `"not_pursuing"`, so attempts recorded before the 4-state
/// model still read correctly.
public enum ReferralOutcome: String, Sendable, CaseIterable {
    case requested
    case responded
    case submitted = "referred"
    case declined
    case notApplicable = "not_pursuing"

    /// The states a user picks for a real outreach request (excludes the job-level `notApplicable`).
    public static let requestStates: [ReferralOutcome] = [.requested, .responded, .submitted, .declined]

    public var label: String {
        switch self {
        case .requested: "Requested"
        case .responded: "Responded"
        case .submitted: "Submitted"
        case .declined: "Declined"
        case .notApplicable: "N/A"
        }
    }
}

/// The derived per-job referral summary — orthogonal to `JobStatus` (AC #1/#3).
public enum ReferralSummary: String, Sendable, CaseIterable {
    case none // no outreach applies (not in the active funnel, no attempts)
    case needsOutreach = "needs_outreach"
    case requested
    case responded
    case submitted
    case declined
    case notApplicable = "not_applicable"

    public var label: String {
        switch self {
        case .none: "—"
        case .needsOutreach: "Needs outreach"
        case .requested: "Requested"
        case .responded: "Responded"
        case .submitted: "Submitted"
        case .declined: "Declined"
        case .notApplicable: "N/A"
        }
    }

    /// Whether this summary represents an outstanding action (drives the "needs outreach" filter/count).
    public var needsAction: Bool {
        self == .needsOutreach
    }
}

public enum ReferralTracking {
    /// The single status where a *missing* referral reads as "Needs outreach" — the workflow is
    /// apply-first, then ask for a referral to get in the system. Interested jobs aren't nudged (that
    /// would pollute a list you don't actively pursue), and Interview/Offer aren't either (you're
    /// already in the system — a nudge there is noise). (TASK-644 review)
    public static let outreachStatuses: Set<String> = ["applied"]

    /// Statuses where the referral *section* is offered even with no requests yet: Interested (you can
    /// line up a referral) and Applied. Interview/Offer/terminal states only show the section when a
    /// request already exists (see `ReferralSection.isApplicable`), so it's not noise once you're in.
    public static let applicableStatuses: Set<String> = ["pursuing", "applied"]

    /// Minimal projection of a referral attempt for the pure derivation (SwiftData-free, testable).
    public struct Attempt: Sendable, Equatable {
        public let outcome: ReferralOutcome
        public let recipientName: String
        public let recipientIdentifier: String?
        public let requestedAt: Date
        /// When the request reached `responded` (nil until then) — used for follow-up nudges.
        public let respondedAt: Date?
        public init(
            outcome: ReferralOutcome, recipientName: String, recipientIdentifier: String?,
            requestedAt: Date, respondedAt: Date? = nil
        ) {
            self.outcome = outcome
            self.recipientName = recipientName
            self.recipientIdentifier = recipientIdentifier
            self.requestedAt = requestedAt
            self.respondedAt = respondedAt
        }
    }

    /// Derive the job's referral summary from its status + attempts (AC #2/#3/#16). Real requests (any
    /// recipient outreach) take precedence over the `notApplicable` marker; the best state across
    /// parallel requests wins (submitted > responded > requested > declined). A job leaving the funnel
    /// keeps recorded attempts but is no longer "Needs outreach".
    public static func summary(jobStatus: String, attempts: [Attempt]) -> ReferralSummary {
        let real = attempts.filter { $0.outcome != .notApplicable }
        if real.contains(where: { $0.outcome == .submitted }) { return .submitted }
        if real.contains(where: { $0.outcome == .responded }) { return .responded }
        if real.contains(where: { $0.outcome == .requested }) { return .requested }
        if !real.isEmpty { return .declined } // real requests exist but none active → all declined
        if attempts.contains(where: { $0.outcome == .notApplicable }) { return .notApplicable }
        return outreachStatuses.contains(jobStatus) ? .needsOutreach : .none
    }

    // MARK: - Per-state dates & reverting (TASK-644)

    /// The four per-state dates of a request. `requested` is always set (the ask date); the others are
    /// populated as the request reaches each state and cleared when the user reverts to an earlier state.
    public struct StateDates: Sendable, Equatable {
        public var requested: Date
        public var responded: Date?
        public var submitted: Date?
        public var declined: Date?
        public init(requested: Date, responded: Date? = nil, submitted: Date? = nil, declined: Date? = nil) {
            self.requested = requested
            self.responded = responded
            self.submitted = submitted
            self.declined = declined
        }
    }

    /// Normalize a request's per-state dates for a chosen `outcome`, stamping the reached state's date
    /// (defaulting to `now` when newly reached) and clearing the dates of states that don't belong to
    /// that outcome — so reverting to an earlier state (to fix a mistake) drops the later milestones.
    /// `submitted` and `declined` are mutually exclusive; `responded` may be skipped (requested →
    /// submitted/declined directly), so it's preserved when already set.
    public static func normalizedDates(outcome: ReferralOutcome, dates: StateDates, now: Date) -> StateDates {
        var out = StateDates(requested: dates.requested)
        switch outcome {
        case .requested, .notApplicable:
            break // only the request date survives
        case .responded:
            out.responded = dates.responded ?? now
        case .submitted:
            out.responded = dates.responded
            out.submitted = dates.submitted ?? now
        case .declined:
            out.responded = dates.responded
            out.declined = dates.declined ?? now
        }
        return out
    }

    /// The date of a request's *current* state, for row/badge display — the reached state's own date,
    /// falling back to the request date when that state's date is somehow missing.
    public static func stateDate(outcome: ReferralOutcome, dates: StateDates) -> Date {
        switch outcome {
        case .requested, .notApplicable: dates.requested
        case .responded: dates.responded ?? dates.requested
        case .submitted: dates.submitted ?? dates.requested
        case .declined: dates.declined ?? dates.requested
        }
    }

    // MARK: - Follow-up nudges (TASK-644 Phase 2)

    /// A stale referral request that warrants a follow-up nudge on the dashboard.
    public struct ReferralNudge: Sendable, Equatable {
        public enum Kind: String, Sendable { case awaitingResponse, awaitingSubmission }
        public let kind: Kind
        /// The date the nudge counts from — the latest request (awaitingResponse) or the latest
        /// response (awaitingSubmission).
        public let since: Date
        public init(kind: Kind, since: Date) {
            self.kind = kind
            self.since = since
        }
    }

    /// Default grace periods before a request/response reads as stale.
    public static let requestedGraceDays = 4
    public static let respondedGraceDays = 7

    /// Whether a job's referral requests need a follow-up, from its most-advanced *active* request: a
    /// Responded-but-not-Submitted request older than `respondedGraceDays`, else a Requested-but-
    /// unanswered one older than `requestedGraceDays`. Submitted / declined-only / N-A never nudge.
    public static func followUp(
        attempts: [Attempt], now: Date,
        requestedGraceDays: Int = requestedGraceDays, respondedGraceDays: Int = respondedGraceDays
    ) -> ReferralNudge? {
        let real = attempts.filter { $0.outcome != .notApplicable }
        guard !real.isEmpty else { return nil }
        if real.contains(where: { $0.outcome == .submitted }) { return nil } // already landed
        let responded = real.filter { $0.outcome == .responded }
        if let since = responded.map({ $0.respondedAt ?? $0.requestedAt }).max() {
            return now.timeIntervalSince(since) >= Double(respondedGraceDays) * 86400
                ? ReferralNudge(kind: .awaitingSubmission, since: since) : nil
        }
        let requested = real.filter { $0.outcome == .requested }
        if let since = requested.map(\.requestedAt).max() {
            return now.timeIntervalSince(since) >= Double(requestedGraceDays) * 86400
                ? ReferralNudge(kind: .awaitingResponse, since: since) : nil
        }
        return nil // only declined requests remain
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

    /// The first prior real request whose recipient matches `name`/`identifier` (AC #6) — so the UI can
    /// warn (with its date) before recording another outreach to the same person. `notApplicable` markers
    /// and empty keys never match.
    public static func duplicateAttempt(name: String?, identifier: String?, among attempts: [Attempt]) -> Attempt? {
        let key = recipientKey(name: name, identifier: identifier)
        guard !key.isEmpty else { return nil }
        return attempts.first { attempt in
            attempt.outcome != .notApplicable
                && recipientKey(name: attempt.recipientName, identifier: attempt.recipientIdentifier) == key
        }
    }
}
