import Foundation

// MARK: - JobDetailProjection
//
// Typed read model derived from a Job's raw extracted JSON and manual overrides.
// Centralizes all JSON parsing so SwiftUI views never touch extractedJSON directly.

public struct JobDetailProjection {
    public let summary: String?
    public let requirements: [String]
    public let niceToHaves: [String]
    public let skills: [String]

    public init(job: Job) {
        let dict = Self.parseJSON(job.extractedJSON)
        summary = dict?["summary"] as? String
        requirements = (dict?["requirements"] as? [String]) ?? []
        niceToHaves = (dict?["nice_to_have"] as? [String])
            ?? (dict?["nice_to_haves"] as? [String]) ?? []

        // Non-empty manual overrides take precedence over extracted skills.
        // An empty array "[]" is the default and means "no overrides yet — use extracted."
        if let data = job.manualOverridesJSON.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
           !arr.isEmpty {
            skills = arr
        } else {
            skills = (dict?["skills"] as? [String]) ?? []
        }
    }

    private static func parseJSON(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }
}

// MARK: - FitScoreProjection
//
// Typed read model derived from a JobFitScore's raw fitScoreJSON.

public struct FitDimension: Sendable {
    public let name: String
    public let score: Int
    public let rationale: String?
}

public struct FitScoreProjection {
    public let requirementsMet: [String]
    public let requirementsNotMet: [String]
    public let dimensions: [FitDimension]

    public init(fitScore: JobFitScore) {
        let dict = Self.parseJSON(fitScore.fitScoreJSON)
        requirementsMet = (dict?["requirements_met"] as? [String]) ?? []
        requirementsNotMet = (dict?["requirements_not_met"] as? [String]) ?? []
        dimensions = (dict?["dimensions"] as? [[String: Any]])?.compactMap { d in
            guard let name = d["name"] as? String, let score = d["score"] as? Int else { return nil }
            return FitDimension(name: name, score: score, rationale: d["rationale"] as? String)
        } ?? []
    }

    private static func parseJSON(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }
}

// MARK: - Salary display

public enum SalaryDisplay {
    /// Formats salary fields into a compact display string, e.g. "$120k–$160k".
    /// Returns nil when both min and max are absent.
    public static func text(min: Int?, max: Int?, currency: String?) -> String? {
        let sym: String
        switch currency ?? "USD" {
        case "GBP": sym = "£"
        case "EUR": sym = "€"
        default:    sym = "$"
        }
        let k: (Int) -> String = { v in v >= 1000 ? "\(v / 1000)k" : "\(v)" }
        if let lo = min, let hi = max { return "\(sym)\(k(lo))–\(sym)\(k(hi))" }
        if let lo = min { return "\(sym)\(k(lo))+" }
        if let hi = max { return "up to \(sym)\(k(hi))" }
        return nil
    }
}
