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

        /// Which direction this kind pushes a score. `alwaysCredit` and `neverCredit` have opposite
        /// effects on every job, and in one undifferentiated list that difference is invisible —
        /// which is the whole reason the list gets hard to reason about past a handful of entries.
        public enum Polarity: Sendable {
            /// Raises scores: the requirement is credited.
            case credits
            /// Lowers scores: a confirmed gap, penalised.
            case penalises
            /// Removes the requirement from scoring entirely, in neither direction.
            case neutral
        }

        public var polarity: Polarity {
            switch self {
            case .alwaysCredit: .credits
            case .neverCredit: .penalises
            case .notARequirement, .jobSpecific: .neutral
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
    ///
    /// Matching is on **whole words** — see `matches(phrase:in:)`. Substring matching let the
    /// three-character phrase `IDE` fire on *provide*, *identify* and *ideally*.
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

// MARK: - Editing

public extension ScoringFeedback {
    /// A copy with the user-editable fields replaced, keeping everything that identifies it.
    ///
    /// `id`, `jobNumber` and `createdAt` are deliberately *not* editable. Delete-and-recreate was the
    /// only way to narrow an over-broad phrase, and it threw away exactly those three — the note's
    /// context, the job that motivated the rule, and the age that tells you whether it predates your
    /// current résumé.
    func updating(phrase: String? = nil, kind: Kind? = nil, note: String? = nil) -> ScoringFeedback {
        ScoringFeedback(
            id: id,
            phrase: phrase ?? self.phrase,
            kind: kind ?? self.kind,
            jobNumber: jobNumber,
            note: note ?? self.note,
            createdAt: createdAt
        )
    }
}

// MARK: - Phrase matching

public extension ScoringFeedback {
    /// Shortest phrase that may be saved. Below this a phrase carries too little meaning to identify
    /// a capability, even matched as a whole word.
    static let minimumPhraseLength = 3

    /// Does `text` contain `phrase` as whole words?
    ///
    /// Plain `contains` was the original test, and it failed badly in production: `IDE` — captured
    /// from a job whose entire requirement text was the string "IDE" — matched *provide*, *identify*,
    /// *ideally*, *identity* and *alongside*, force-crediting 159 requirements across 120 of 415 jobs
    /// and inflating 28 scores by up to 34 points.
    ///
    /// A match must begin and end on a word boundary, but only where the phrase itself has a word
    /// character at that edge: a phrase ending in "." or "—" still matches text that does.
    static func matches(phrase: String, in text: String) -> Bool {
        let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        let haystack = text.lowercased()
        func isWord(_ c: Character) -> Bool {
            c.isLetter || c.isNumber
        }
        // Only require a boundary on an edge where the phrase could otherwise run into a word.
        let guardLeading = needle.first.map(isWord) ?? false
        let guardTrailing = needle.last.map(isWord) ?? false

        var searchFrom = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchFrom ..< haystack.endIndex) {
            let leadingOK = !guardLeading || found.lowerBound == haystack.startIndex
                || !isWord(haystack[haystack.index(before: found.lowerBound)])
            let trailingOK = !guardTrailing || found.upperBound == haystack.endIndex
                || !isWord(haystack[found.upperBound])
            if leadingOK, trailingOK { return true }
            guard found.lowerBound < haystack.endIndex else { break }
            searchFrom = haystack.index(after: found.lowerBound)
        }
        return false
    }

    /// Why a phrase can't be saved as a correction, or `nil` when it's usable.
    ///
    /// Checked when the correction is authored rather than when it fires: a rule that quietly matches
    /// a third of the corpus is invisible until someone audits scores months later.
    static func rejectionReason(forPhrase phrase: String) -> String? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a phrase to match on." }
        if trimmed.count < minimumPhraseLength {
            return "Too short to identify a requirement — use at least \(minimumPhraseLength) characters."
        }
        guard trimmed.contains(where: { $0.isLetter || $0.isNumber }) else {
            return "Needs at least one word to match on."
        }
        return nil
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
        var sawIgnore = false
        var sawMet = false
        for entry in self {
            guard ScoringFeedback.matches(phrase: entry.phrase, in: requirement) else { continue }
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

// MARK: - Blast radius

/// How far a candidate correction would reach across the scored corpus.
///
/// Shown before saving, because the failure mode this guards against is invisible afterwards: a rule
/// that force-credits a third of every job's requirements looks identical, in the settings list, to
/// one that hits the single requirement it was written for.
public struct FeedbackMatchPreview: Sendable, Equatable {
    public let matchingRequirements: Int
    public let matchingJobs: Int
    public let totalRequirements: Int
    public let totalJobs: Int

    public init(matchingRequirements: Int, matchingJobs: Int, totalRequirements: Int, totalJobs: Int) {
        self.matchingRequirements = matchingRequirements
        self.matchingJobs = matchingJobs
        self.totalRequirements = totalRequirements
        self.totalJobs = totalJobs
    }

    /// Share of all scored requirements this would touch.
    public var requirementShare: Double {
        totalRequirements > 0 ? Double(matchingRequirements) / Double(totalRequirements) : 0
    }

    /// Share of scored jobs whose score would move.
    public var jobShare: Double {
        totalJobs > 0 ? Double(matchingJobs) / Double(totalJobs) : 0
    }

    /// Reaching a third of all jobs is not a correction to one wrong assessment — it's a policy
    /// change, and almost always an accident. `IDE` reached 30% of jobs; every deliberate rule
    /// measured so far reached well under 1%.
    public var isImplausiblyBroad: Bool {
        matchingJobs > 1 && jobShare > 0.10
    }
}
