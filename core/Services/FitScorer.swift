import Foundation

// MARK: - Types

/// Output from a live fit-scoring LLM call: computed score + merged JSON for storage.
/// The JSON merges the raw LLM explanation fields (dimensions/rationales, requirements_met,
/// summary) with the computed score fields so nothing is lost on the way to the database.
public struct FitScoreOutput: Sendable {
    public let score: FitScoreResult
    /// Merged JSON ready to store in `fitScoreJSON`. Nil only if serialization fails.
    public let fitScoreJSON: String?
    /// Character count of the prompt sent to the LLM.
    public let promptChars: Int
    /// Character count of the raw LLM response.
    public let responseChars: Int
    /// Actual provider-reported token usage when available (TASK-538); nil when unreported.
    public let promptTokens: Int?
    public let completionTokens: Int?
    /// Model identifier reported by the provider (mirrors extraction's `extractionModel`).
    public let modelReturned: String
    /// Format the provider actually used for this response (may be a downgrade) — TASK-454.
    public let responseFormat: ResponseFormat
}

/// Result of a fit score computation.
public struct FitScoreResult: Codable, Sendable {
    /// Overall score 0–100 (weighted sum minus penalty, floored at 0).
    public let overall: Int
    /// Per-dimension raw scores (0–100 each), keyed by dimension name.
    public let breakdown: [String: Double]
    /// Points subtracted by the penalty model (0–60, the cap).
    public let penalty: Int
    /// Human-readable strings describing what triggered each penalty point.
    public let penaltyReasons: [String]
    /// Score weights used during computation (for audit / rescore).
    public let scoreWeights: [String: Double]

    public init(
        overall: Int,
        breakdown: [String: Double],
        penalty: Int,
        penaltyReasons: [String],
        scoreWeights: [String: Double]
    ) {
        self.overall = overall
        self.breakdown = breakdown
        self.penalty = penalty
        self.penaltyReasons = penaltyReasons
        self.scoreWeights = scoreWeights
    }
}

// MARK: - FitScorer

/// Pure, deterministic fit-score math ported from server/extract.js and server/rescore.js.
/// No SwiftData, no SwiftUI, no networking — safe to call from any context.
public enum FitScorer {
    // MARK: Dimension weights (must total 1.0)

    // TASK-602: preferred qualifications now carry real weight — in a competitive market, missing
    // nice-to-haves get you filtered out — and experience_level is trimmed because in practice the LLM
    // scores it near-constant (~98), so it wasted discrimination at 0.20. Weights must total 1.0.
    public static let dimensionWeights: [String: Double] = [
        "required_qualifications": 0.40,
        "preferred_qualifications": 0.20,
        "skills": 0.15,
        "domain_fit": 0.15,
        "experience_level": 0.10
    ]

    // MARK: - Requirement gaps + penalty model (TASK-602)

    /// A qualification the candidate does not fully satisfy, tagged by whether the job listed it as a
    /// hard requirement or a preferred/nice-to-have, and how far short the resume falls.
    public struct RequirementGap: Sendable, Equatable {
        public enum Kind: String, Sendable { case required, preferred }
        public enum Status: String, Sendable { case partial, missing }
        public let requirement: String
        public let kind: Kind
        public let status: Status
        public init(requirement: String, kind: Kind, status: Status) {
            self.requirement = requirement
            self.kind = kind
            self.status = status
        }
    }

    /// Points subtracted for one gap, from the kind×status grid. This replaces the old hardware-only
    /// keyword heuristic: severity now comes from the LLM's per-job judgment (required vs preferred,
    /// partial vs missing) rather than a fixed word list. Preferred treatment is intentionally
    /// aggressive — a missing nice-to-have costs nearly as much as a missing must-have (TASK-602).
    ///
    ///                 missing   partial
    ///   required        12        6
    ///   preferred       10        5
    public static func penaltyPoints(kind: RequirementGap.Kind, status: RequirementGap.Status) -> Int {
        switch (kind, status) {
        case (.required, .missing): 12
        case (.required, .partial): 6
        case (.preferred, .missing): 10
        case (.preferred, .partial): 5
        }
    }

    // MARK: Penalty cap

    public static let penaltyCap: Int = 60

    // MARK: Assessment prompt version

    /// Bumped whenever the scoring prompt changes in a way that alters what the model returns, and
    /// stamped into every stored score.
    ///
    /// Without it a corpus silently mixes populations: after the named-technology rule tightened what
    /// counts as "met", new scores are stricter than the 171 already stored, and a `min_score` filter
    /// would compare the two as if they were the same measurement. Recomputing can't reconcile them —
    /// the arithmetic is unchanged, it's the model's judgment that moved — so consumers need to be
    /// able to tell which prompt produced a score.
    ///
    /// v1 = original.
    /// v2 = named technologies require literal evidence to score "met".
    /// v3 = a menu of alternatives is judged against the option the posting emphasises, and
    ///      domain_fit means the industry and product rather than transferable craft.
    public static let assessmentPromptVersion = 3

    // MARK: - Non-discriminating requirements

    /// A requirement no candidate could fail, so a gap against it is invented rather than found.
    ///
    /// Handled in code rather than in the prompt on purpose. Instructing the model to "omit" this
    /// class made things markedly worse on a weak model (gemini-3.1-flash-lite): it scored the items
    /// `met` instead of omitting them, and the extra broad rule diluted the alternatives and
    /// domain-fit rules that were working — job #231 went back from a correct 60 to 96 and #718 from
    /// 75 to 99. A deterministic filter can't be misapplied, can't compete with other instructions,
    /// and applies to already-stored scores on recompute at no cost.
    ///
    /// Two families, both satisfiable by disposition rather than by anything the candidate has done:
    ///   - an escape clause that reduces the requirement to aptitude — "experience with, or capacity
    ///     to learn, JIRA" is satisfied by anyone, so #718 losing 6 points to it was noise;
    ///   - alignment with company values or culture, which a résumé cannot evidence either way.
    ///
    /// Deliberately narrow: it matches the *escape clause*, not the underlying skill. "Experience
    /// with JIRA" is still a real, assessable requirement — only "or capacity to learn JIRA" is not.
    public static func isNonDiscriminating(requirement: String) -> Bool {
        let text = requirement.lowercased()
        let aptitudeEscapes = [
            "capacity to learn", "ability to learn", "willingness to learn", "eagerness to learn",
            "aptitude to learn", "willing to learn", "open to learning", "interest in learning"
        ]
        if aptitudeEscapes.contains(where: { text.contains($0) }) { return true }
        // "Alignment with <company>'s core values", "embodies our culture", "passion for our mission".
        let dispositionMarkers = [
            "core values",
            "company values",
            "our values",
            "cultural fit",
            "culture fit",
            "embodies our culture",
            "passion for our mission"
        ]
        return dispositionMarkers.contains(where: { text.contains($0) })
    }

    /// Build the gap list from the LLM's `requirement_assessments` (raw dicts). Only `partial`/`missing`
    /// items become gaps (`met` is not a gap). `kind` comes from the assessment; when it's absent
    /// (legacy scores that predate the tag) it defaults to `.required` so an unknown gap is treated as
    /// the heavier tier.
    public static func requirementGaps(
        fromAssessments assessments: [[String: Any]],
        feedback: [ScoringFeedback] = [],
        jobNumber: Int? = nil
    ) -> [RequirementGap] {
        assessments.compactMap { item in
            guard let requirement = item["requirement"] as? String,
                  let statusRaw = item["status"] as? String,
                  var status = RequirementGap.Status(rawValue: statusRaw) else {
                // A `met` assessment is normally not a gap — unless the user has said they don't
                // have the thing, in which case their correction outranks the model's judgment.
                guard let requirement = item["requirement"] as? String,
                      feedback.verdict(forRequirement: requirement, jobNumber: jobNumber) == .forceMissing
                else { return nil }
                let kind = RequirementGap.Kind(rawValue: (item["kind"] as? String) ?? "") ?? .required
                return RequirementGap(requirement: requirement, kind: kind, status: .missing)
            }
            switch feedback.verdict(forRequirement: requirement, jobNumber: jobNumber) {
            case .forceMissing: status = .missing
            case .ignore, .forceMet: return nil // met and ignored both mean: not a gap
            case .none: break
            }
            // Never penalise something no candidate could fail.
            guard !isNonDiscriminating(requirement: requirement) else { return nil }
            let kind = RequirementGap.Kind(rawValue: (item["kind"] as? String) ?? "") ?? .required
            return RequirementGap(requirement: requirement, kind: kind, status: status)
        }
    }

    // MARK: - Dimension validation (TASK-453)

    public enum FitDimensionError: Error, Equatable {
        case notAnArray
        case missing([String]) // expected dimensions absent from the response
        case unknown(String) // a dimension name not in the expected contract
        case duplicate(String) // the same dimension appeared twice
        case nonNumericScore(String) // a dimension's score wasn't a number
    }

    /// Validate that the LLM `dimensions` array carries EXACTLY the expected dimension names, each
    /// once, with numeric scores — before computing/persisting a fit score (TASK-453). A malformed
    /// response (wrong/missing/duplicate names, non-numeric score) throws so it fails as a retryable
    /// schema error instead of being stored as a misleading low score (missing dims scoring 0).
    public static func validateDimensions(_ raw: Any?) throws -> [String: Double] {
        guard let arr = raw as? [[String: Any]] else { throw FitDimensionError.notAnArray }
        var result: [String: Double] = [:]
        var seen: Set<String> = []
        for item in arr {
            guard let name = item["name"] as? String, dimensionWeights[name] != nil else {
                throw FitDimensionError.unknown((item["name"] as? String) ?? "<missing name>")
            }
            if seen.contains(name) { throw FitDimensionError.duplicate(name) }
            seen.insert(name)
            if let d = item["score"] as? Double {
                result[name] = min(100, max(0, d.rounded()))
            } else if let i = item["score"] as? Int {
                result[name] = min(100, max(0, Double(i)))
            } else {
                throw FitDimensionError.nonNumericScore(name)
            }
        }
        let missing = Set(dimensionWeights.keys).subtracting(seen)
        if !missing.isEmpty { throw FitDimensionError.missing(missing.sorted()) }
        return result
    }

    // MARK: - Public API

    /// Compute a fit score from per-dimension scores and requirement gaps.
    ///
    /// - Parameters:
    ///   - dimensions: Dictionary mapping dimension name to raw 0–100 score.
    ///   - gaps: Qualifications the candidate does not fully satisfy (kind + partial/missing), which
    ///     drive the severity-weighted penalty.
    /// - Returns: `FitScoreResult` with the final score, breakdown, and penalty details.
    /// The weighted dimension score before penalties.
    ///
    /// One implementation, shared by scoring and by anything reporting the base separately. When the
    /// projection layer reimplemented this it diverged on the first try — `weights.values.reduce`
    /// sums in dictionary order, and 89.5 / 1.0000000000000002 rounds to 89 rather than 90.
    public static func baseScore(breakdown: [String: Double]) -> Int {
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        // Sorted order in BOTH accumulations: floating-point addition isn't associative, so summing
        // the weights in a different order than the scores can shift the quotient across a rounding
        // boundary.
        for name in dimensionWeights.keys.sorted() {
            let weight = dimensionWeights[name] ?? 0
            totalWeight += weight
            weightedSum += min(100, max(0, (breakdown[name] ?? 0).rounded())) * weight
        }
        guard totalWeight > 0 else { return 0 }
        return Int((weightedSum / totalWeight).rounded())
    }

    public static func computeScore(
        dimensions: [String: Double],
        gaps: [RequirementGap] = []
    ) -> FitScoreResult {
        // Weighted sum: sum(score * weight) / sum(ALL expected weights)
        // Missing dimensions score 0 so a partial response doesn't inflate the score.
        // Iterate in SORTED key order (not raw dictionary order): floating-point addition isn't
        // associative, and Dictionary iteration order is nondeterministic, so an unordered sum could
        // land just above/below a .5 boundary and round to a different integer across runs/machines
        // (bit us in CI: 70 vs 71 for the same input). Sorted order makes the score deterministic.
        var breakdown: [String: Double] = [:]
        for name in dimensionWeights.keys.sorted() {
            breakdown[name] = min(100, max(0, (dimensions[name] ?? 0).rounded()))
        }
        let baseScore = baseScore(breakdown: breakdown)

        // Penalty: sum the kind×status cost per gap, capped.
        var penaltyTotal = 0
        var penaltyReasons: [String] = []
        for gap in gaps {
            let cost = penaltyPoints(kind: gap.kind, status: gap.status)
            penaltyTotal += cost
            penaltyReasons.append("\(gap.requirement) (\(gap.kind.rawValue)/\(gap.status.rawValue), -\(cost))")
        }
        let penalty = min(penaltyTotal, penaltyCap)

        let overall = max(0, baseScore - penalty)

        return FitScoreResult(
            overall: overall,
            breakdown: breakdown,
            penalty: penalty,
            penaltyReasons: penaltyReasons,
            scoreWeights: dimensionWeights
        )
    }

    /// Recompute a fit score from an existing `fitScoreJSON` string (no LLM).
    ///
    /// This mirrors rescore.js: parse the stored JSON, re-run weighting + penalty,
    /// and return the updated result. Returns `nil` if the JSON is invalid or
    /// contains no usable dimension data.
    public static func rescoreFromJSON(
        _ json: String,
        feedback: [ScoringFeedback] = [],
        jobNumber: Int? = nil
    ) -> FitScoreResult? {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Dimensions can be stored either as the legacy array-of-objects format
        // (from the JS side) or as the Swift breakdown dictionary.
        let dimensionScores: [String: Double]

        if let dimensionsArray = raw["dimensions"] as? [[String: Any]] {
            // Legacy JS format: [{name: "...", score: N, rationale: "..."}, ...]
            guard !dimensionsArray.isEmpty else { return nil }
            var dict: [String: Double] = [:]
            for dim in dimensionsArray {
                if let name = dim["name"] as? String, let score = dim["score"] as? Double {
                    dict[name] = score
                } else if let name = dim["name"] as? String, let score = dim["score"] as? Int {
                    dict[name] = Double(score)
                }
            }
            dimensionScores = dict
        } else if let breakdown = raw["breakdown"] as? [String: Double] {
            // Swift format: {"required_qualifications": 80.0, ...}
            dimensionScores = breakdown
        } else {
            return nil
        }

        // An INCOMPLETE dimension set is refused, not silently scored. `computeScore` treats a
        // missing dimension as 0 — correct when validating a live response (a partial answer must not
        // inflate), but wrong here: recompute is advertised as free and safe, and a stored score
        // missing one dimension would quietly lose up to 40 points on an operation the user was told
        // just re-runs the arithmetic. Returning nil leaves the existing score untouched instead.
        // (The live path already rejects these via `validateDimensions`.)
        guard !dimensionScores.isEmpty,
              Set(dimensionWeights.keys).isSubset(of: Set(dimensionScores.keys))
        else { return nil }

        // Gaps: prefer the structured per-requirement assessments (kind + partial/missing). Fall back
        // to the legacy free-form requirements_not_met (treated as missing *required* gaps) for old
        // scores that predate the assessments array.
        let gaps: [RequirementGap]
        if let assessments = raw["requirement_assessments"] as? [[String: Any]], !assessments.isEmpty {
            gaps = requirementGaps(fromAssessments: assessments, feedback: feedback, jobNumber: jobNumber)
        } else {
            let legacy = (raw["requirements_not_met"] as? [String]) ?? []
            gaps = legacy.map { RequirementGap(requirement: $0, kind: .required, status: .missing) }
        }
        return computeScore(dimensions: dimensionScores, gaps: gaps)
    }

    /// Encode a `FitScoreResult` to a JSON string for storage in `Job.fitScoreJSON`
    /// or `JobFitScore.fitScoreJSON`.
    public static func encode(_ result: FitScoreResult) -> String? {
        guard let data = try? JSONEncoder().encode(result) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Build merged JSON that retains raw LLM explanation fields (dimensions with rationales,
    /// requirements_met, summary) while overlaying the computed score fields.
    /// Use this when storing a freshly scored result so the UI can render explanations.
    public static func buildMergedJSON(result: FitScoreResult, rawLLMDict: [String: Any]) -> String? {
        var merged = rawLLMDict
        merged["overall"] = result.overall
        merged["breakdown"] = result.breakdown
        merged["penalty"] = result.penalty
        merged["penaltyReasons"] = result.penaltyReasons
        merged["scoreWeights"] = result.scoreWeights
        // Preserve the version a score was ASSESSED under. A recompute re-runs the arithmetic over
        // the model's existing judgments, so it must not relabel an old assessment as a new one.
        if merged["assessment_prompt_version"] == nil {
            merged["assessment_prompt_version"] = rawLLMDict["assessment_prompt_version"] ?? 1
        }
        // Ensure requirements_not_met key matches projection expectations
        if merged["requirements_not_met"] == nil {
            merged["requirements_not_met"] = result.penaltyReasons
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a `FitScoreResult` from a JSON string (inverse of `encode`).
    public static func decode(from json: String) -> FitScoreResult? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FitScoreResult.self, from: data)
    }
}
