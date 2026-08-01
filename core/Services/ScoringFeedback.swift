import Foundation

/// A correction the user made to a requirement assessment, captured where they saw it go wrong.
///
/// The alternative was a "never credit these" textbox in Settings, which asks the user to predict in
/// the abstract what the model will get wrong. The natural moment is when they're looking at a wrong
/// answer — so the list is built as a *by-product* of flagging, and Settings shows it rather than
/// demanding it be authored.
///
/// Feedback is applied **deterministically**, never by appending prose to the prompt. That isn't a
/// stylistic choice: adding one broad rule to the scoring prompt measurably degraded a weak model
/// (job #231 regressed from a correct 60 back to 96 because the new instruction diluted the rules
/// that were working). Accumulating user notes would be worse, and would degrade silently.
public struct ScoringFeedback: Codable, Sendable, Identifiable, Equatable {
    /// What the user is telling us, which determines the mechanism — the reasons differ in effect,
    /// not just in wording.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// "I do have this." The commonest correction: the model found no evidence in the résumé,
        /// but the user does have the experience. Scores `met` and costs nothing.
        ///
        /// Worth noting when it fires: if the résumé doesn't state the thing, a recruiter or ATS
        /// won't credit it either. Silencing the scorer fixes the number, not the application.
        case alwaysCredit
        /// "I don't have this." A genuine requirement the user genuinely fails — CUDA, PCI DSS,
        /// electrical engineering. Scores `missing` and IS penalised: it's a real gap and hiding it
        /// would misrepresent the role's fit.
        case neverCredit
        /// "This isn't a real requirement." Satisfiable by anyone, or unevidenceable from a résumé —
        /// "capacity to learn JIRA", company values. Costs nothing and is hidden, because a zero-cost
        /// gap still reads as something to fix.
        case notARequirement
        /// "Wrong for this job only." No effect beyond the one posting.
        case jobSpecific

        public var label: String {
            switch self {
            case .alwaysCredit: "I do have this"
            case .neverCredit: "I don't have this"
            case .notARequirement: "This isn't a real requirement"
            case .jobSpecific: "Wrong for this job only"
            }
        }

        public var explanation: String {
            switch self {
            case .neverCredit:
                "Any requirement mentioning this scores as missing, on every job. Use it for tools, "
                    + "standards or backgrounds you couldn't defend in an interview."
            case .notARequirement:
                "Never counted as a gap anywhere — for things no candidate could fail, like "
                    + "\"capacity to learn\" or alignment with company values."
            case .alwaysCredit:
                "Scores as met everywhere, with no penalty. If your résumé doesn't actually say it, "
                    + "consider adding it — a recruiter reading the same résumé will miss it too."
            case .jobSpecific:
                "Applies only to this posting."
            }
        }
    }

    public let id: String
    /// The phrase the rule matches on, lowercased at comparison time. Narrower is better: "electrical
    /// engineering" is a good entry, bare "electrical" also fires on "partner with electrical teams".
    public let phrase: String
    public let kind: Kind
    /// The job it was flagged from — context for the user, and the scope for `.jobSpecific`.
    public let jobNumber: Int?
    /// Free text. Deliberately NOT fed to the model; it's a note to self, and a candidate for later
    /// distillation into structure behind an approval step.
    public let note: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        phrase: String,
        kind: Kind,
        jobNumber: Int? = nil,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.phrase = phrase
        self.kind = kind
        self.jobNumber = jobNumber
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - Applying feedback

public extension [ScoringFeedback] {
    /// How a requirement should be treated, given this feedback.
    enum Verdict: Equatable {
        /// Score `missing` and penalise — a real gap the user has confirmed.
        case forceMissing
        /// Score `met` — the user has confirmed they have it despite the model finding no evidence.
        case forceMet
        /// Drop entirely: no penalty, not displayed.
        case ignore
        /// No feedback applies.
        case none
    }

    /// Match on the requirement text. Global rules apply everywhere; `.jobSpecific` only to its job.
    ///
    /// `forceMissing` wins over everything else when several match: the user has said they don't
    /// have the thing, and suppressing a real gap is the most harmful error available here.
    func verdict(forRequirement requirement: String, jobNumber: Int?) -> Verdict {
        let text = requirement.lowercased()
        var sawIgnore = false
        var sawMet = false
        for entry in self {
            let phrase = entry.phrase.trimmingCharacters(in: .whitespaces).lowercased()
            guard !phrase.isEmpty, text.contains(phrase) else { continue }
            switch entry.kind {
            case .jobSpecific:
                // Scoped: a one-off misread must not silently change every other job.
                if let jobNumber, entry.jobNumber == jobNumber { sawIgnore = true }
            case .neverCredit:
                return .forceMissing
            case .notARequirement:
                sawIgnore = true
            case .alwaysCredit:
                sawMet = true
            }
        }
        if sawIgnore { return .ignore }
        return sawMet ? .forceMet : .none
    }
}
