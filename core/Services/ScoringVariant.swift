import Foundation

/// A way of turning one LLM assessment into a 0–100 fit score.
///
/// Exists so alternatives can be compared **without reimplementing the arithmetic**. Every
/// experiment run so far lived in a throwaway script that re-derived the maths in another language,
/// which is the divergence this codebase has already been bitten by — an independent base-score
/// reimplementation disagreed with `FitScorer` by a point on the very first job. Tests, the
/// `ScoreLab` CLI and the app now all score through this one type, so a variant that looks good in an
/// experiment is the same variant that ships.
///
/// Re-scoring is free: every analysis is stored as JSON, so a variant can be evaluated over the whole
/// corpus with no LLM calls.
public enum ScoringVariant: Sendable, Equatable {
    /// What ships today: weighted dimension scores, minus the normalised requirement penalty.
    ///
    /// Two independent LLM judgements feed this — the five dimension numbers AND the per-requirement
    /// verdicts — so it carries two independent sources of run-to-run variance. Measured on identical
    /// input, the dimensions alone moved the base 26 points.
    case current

    /// Score is purely the share of requirements met. No dimension numbers at all, so the score
    /// becomes a deterministic function of the verdicts.
    ///
    /// Maximally stable, but **compresses badly**: requirement lists are generous (models mark most
    /// requirements met or partial), so over the real corpus this puts the median at 90 and half the
    /// jobs at 90+, leaving no top to rank. Kept as the stability baseline, not as a candidate.
    case verdictShare(partialCredit: Double = 0.5)

    /// The share of requirements met, blended with only the judgements a requirement list cannot
    /// express.
    ///
    /// No posting carries a bullet saying "must have worked in our industry", so `domain_fit` — and
    /// to a lesser extent `experience_level` — encode something the verdicts structurally cannot.
    /// Dropping the other three dimensions removes most of the variance surface while keeping the
    /// spread that makes the top of the list rankable.
    case hybrid(verdictWeight: Double = 0.5, partialCredit: Double = 0.5)

    public var name: String {
        switch self {
        case .current: "current"
        case let .verdictShare(p): "verdict-share(partial \(p))"
        case let .hybrid(w, p): "hybrid(verdicts \(Int(w * 100))%, partial \(p))"
        }
    }
}

public extension FitScorer {
    /// Weight of one requirement in the verdict share. A hard requirement counts for three
    /// nice-to-haves; the ratio is deliberate rather than fitted, and is the thing to tune first if
    /// preferred qualifications start dominating.
    static let requiredShareWeight = 3.0
    static let preferredShareWeight = 1.0

    /// Dimensions retained by `.hybrid`, and how they blend into the context term. Chosen because a
    /// requirement list can't state either: industry/product background, and whether the candidate is
    /// at the level the role is pitched at.
    static let contextDimensionWeights: [String: Double] = [
        "domain_fit": 0.6,
        "experience_level": 0.4
    ]

    /// Share of the posting's requirements the candidate meets, 0–100.
    ///
    /// `met` counts fully, `partial` at `partialCredit`, `missing` at nothing.
    static func verdictShare(
        assessments: [[String: Any]],
        partialCredit: Double,
        feedback: [ScoringFeedback] = [],
        jobNumber: Int? = nil
    ) -> Double? {
        var earned = 0.0
        var total = 0.0
        for item in assessments {
            guard let requirement = item["requirement"] as? String else { continue }
            // Mirror the gap filtering exactly, or a requirement dropped from the numerator would
            // still sit in the denominator and quietly depress the score.
            let verdict = feedback.verdict(forRequirement: requirement, jobNumber: jobNumber)
            if verdict == .ignore { continue }
            guard !isNonDiscriminating(requirement: requirement) else { continue }

            let kind = RequirementGap.Kind(rawValue: (item["kind"] as? String) ?? "") ?? .required
            let weight = kind == .required ? requiredShareWeight : preferredShareWeight

            let status: String
            switch verdict {
            case .forceMet: status = "met"
            case .forceMissing: status = "missing"
            default: status = (item["status"] as? String) ?? "missing"
            }
            let credit: Double
            switch status {
            case "met": credit = 1.0
            case "partial": credit = partialCredit
            default: credit = 0.0
            }
            earned += weight * credit
            total += weight
        }
        guard total > 0 else { return nil }
        return 100 * earned / total
    }

    /// How many required qualifications the candidate outright misses.
    ///
    /// Surfaced separately because it is the user's actual triage question — "do I meet all of them,
    /// and if not could I survive missing one or two?" — which a single blended number hides.
    static func missingRequiredCount(
        assessments: [[String: Any]],
        feedback: [ScoringFeedback] = [],
        jobNumber: Int? = nil
    ) -> Int {
        requirementGaps(fromAssessments: assessments, feedback: feedback, jobNumber: jobNumber)
            .count { $0.kind == .required && $0.status == .missing }
    }

    /// Score one stored analysis under `variant`.
    ///
    /// `dimensions` may be empty for the verdict-only variant; `.current` and `.hybrid` need it.
    static func score(
        _ variant: ScoringVariant,
        dimensions: [String: Double],
        assessments: [[String: Any]],
        feedback: [ScoringFeedback] = [],
        jobNumber: Int? = nil
    ) -> Int {
        switch variant {
        case .current:
            let gaps = requirementGaps(fromAssessments: assessments, feedback: feedback, jobNumber: jobNumber)
            let counts = assessments.isEmpty
                ? nil
                : requirementCounts(fromAssessments: assessments, feedback: feedback, jobNumber: jobNumber)
            return computeScore(dimensions: dimensions, gaps: gaps, counts: counts).overall

        case let .verdictShare(partial):
            let share = verdictShare(
                assessments: assessments, partialCredit: partial, feedback: feedback, jobNumber: jobNumber
            )
            return Int((share ?? 0).rounded())

        case let .hybrid(verdictWeight, partial):
            guard let share = verdictShare(
                assessments: assessments, partialCredit: partial, feedback: feedback, jobNumber: jobNumber
            ) else {
                // No usable requirements — fall back to the context term rather than scoring 0.
                return Int(contextScore(dimensions: dimensions).rounded())
            }
            let context = contextScore(dimensions: dimensions)
            return Int((verdictWeight * share + (1 - verdictWeight) * context).rounded())
        }
    }

    /// The retained dimensions, blended. Sorted iteration keeps it deterministic — unordered
    /// floating-point addition has already produced off-by-one scores across runs in this file.
    static func contextScore(dimensions: [String: Double]) -> Double {
        var weighted = 0.0
        var total = 0.0
        for name in contextDimensionWeights.keys.sorted() {
            guard let weight = contextDimensionWeights[name] else { continue }
            weighted += min(100, max(0, dimensions[name] ?? 0)) * weight
            total += weight
        }
        return total > 0 ? weighted / total : 0
    }
}
