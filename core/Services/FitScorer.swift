import Foundation

// MARK: - Types

/// Result of a fit score computation.
public struct FitScoreResult: Codable, Sendable {
    /// Overall score 0–100 (weighted sum minus penalty, floored at 0).
    public let overall: Int
    /// Per-dimension raw scores (0–100 each), keyed by dimension name.
    public let breakdown: [String: Double]
    /// Points subtracted by the penalty model (0–50).
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

    public static let dimensionWeights: [String: Double] = [
        "required_qualifications": 0.45,
        "preferred_qualifications": 0.05,
        "skills": 0.15,
        "experience_level": 0.20,
        "domain_fit": 0.15
    ]

    // MARK: Domain-gap keywords (case-insensitive substring match)

    public static let domainGapKeywords: [String] = [
        "asic", "fpga", "rtl", "tapeout", "tape-out", "silicon", "emulation",
        "hyperscaler", "cloud service", "soc ", "vlsi", "gds"
    ]

    // MARK: Penalty cap

    public static let penaltyCap: Int = 50

    // MARK: - Public API

    /// Compute a fit score from per-dimension scores and missing requirements.
    ///
    /// - Parameters:
    ///   - dimensions: Dictionary mapping dimension name to raw 0–100 score.
    ///   - requirementsNotMet: Array of requirement strings the candidate does NOT satisfy.
    /// - Returns: `FitScoreResult` with the final score, breakdown, and penalty details.
    public static func computeScore(
        dimensions: [String: Double],
        requirementsNotMet: [String] = []
    ) -> FitScoreResult {
        // Weighted sum: sum(score * weight) / sum(weights_present)
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        var breakdown: [String: Double] = [:]

        for (name, weight) in dimensionWeights {
            guard let raw = dimensions[name] else { continue }
            let clamped = min(100, max(0, raw.rounded()))
            breakdown[name] = clamped
            weightedSum += clamped * weight
            totalWeight += weight
        }

        let baseScore = if totalWeight > 0 {
            Int((weightedSum / totalWeight).rounded())
        } else {
            0
        }

        // Penalty
        var penaltyPoints = 0
        var penaltyReasons: [String] = []
        for item in requirementsNotMet {
            let lower = item.lowercased()
            let isDomainGap = domainGapKeywords.contains { lower.contains($0) }
            let cost = isDomainGap ? 10 : 5
            penaltyPoints += cost
            penaltyReasons.append(item)
        }
        let penalty = min(penaltyPoints, penaltyCap)

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
    public static func rescoreFromJSON(_ json: String) -> FitScoreResult? {
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

        guard !dimensionScores.isEmpty else { return nil }

        // Handle both JS (requirements_not_met) and Swift (penaltyReasons) key names.
        let requirementsNotMet = (raw["requirements_not_met"] as? [String])
            ?? (raw["penaltyReasons"] as? [String])
            ?? []
        return computeScore(dimensions: dimensionScores, requirementsNotMet: requirementsNotMet)
    }

    /// Encode a `FitScoreResult` to a JSON string for storage in `Job.fitScoreJSON`
    /// or `JobFitScore.fitScoreJSON`.
    public static func encode(_ result: FitScoreResult) -> String? {
        guard let data = try? JSONEncoder().encode(result) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a `FitScoreResult` from a JSON string (inverse of `encode`).
    public static func decode(from json: String) -> FitScoreResult? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FitScoreResult.self, from: data)
    }
}
