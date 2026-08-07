import Foundation

/// Split out of DemoSeeder.swift purely to keep that file under the 800-line limit.
extension BackgroundStore {
    /// Build a fit analysis in the shape the app actually reads, and score it with the real scorer.
    ///
    /// The previous builder emitted `{score, summary, strengths, gaps}` — a schema `FitScoreProjection`
    /// doesn't parse. It reads `requirement_assessments` and `dimensions`, so **every demo job showed
    /// an empty Fit tab**: no requirement rows, no dimension bars, no correction flags. Demo mode
    /// exists to show the app off, and that tab is the thing most worth showing.
    ///
    /// Requirements are decomposed from the seed job's own requirement prose rather than invented, so
    /// the rows on screen correspond to the posting text alongside them. The stored score is whatever
    /// `FitScorer.computeScore` returns for the generated JSON — never a hardcoded number — so the
    /// headline score and the breakdown underneath it cannot contradict each other.
    func makeFitAnalysis(
        fitScore: Int?, requirements: String?, skills: [String],
        seniority: String?, title: String?, jobNum: Int
    ) -> (json: String, score: Int)? {
        guard let target = fitScore else { return nil }

        let required = (requirements ?? "")
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 12 }
        guard !required.isEmpty else { return nil }
        let preferred = skills.prefix(3).map { "Experience with \($0)" }

        // The base is the weighted dimension average, so it can't exceed 100 — which bounds how much
        // penalty a target score can carry. Budget backwards from the target and keep the base ≤ 95,
        // otherwise a mid-range job would need an impossible base to land where the demo wants it.
        let budget = max(0, min(30, 95 - target))
        // Alternate which gap tier is filled first so the demo shows both ✗ and partial rows, rather
        // than every job degrading in the same way.
        let tiers: [(kind: String, status: String, cost: Int)] = jobNum.isMultiple(of: 2)
            ? [
                ("preferred", "missing", 10),
                ("required", "partial", 6),
                ("preferred", "partial", 5),
                ("required", "missing", 12)
            ]
            : [
                ("preferred", "partial", 5),
                ("required", "partial", 6),
                ("preferred", "missing", 10),
                ("required", "missing", 12)
            ]
        var remaining = budget
        var plan: [(kind: String, status: String)] = []
        for tier in tiers where remaining >= tier.cost {
            plan.append((tier.kind, tier.status))
            remaining -= tier.cost
        }

        // Gaps land on the LAST items of each list, so the first requirements a viewer reads are met.
        var reqStatus = [String](repeating: "met", count: required.count)
        var prefStatus = [String](repeating: "met", count: preferred.count)
        for entry in plan {
            if entry.kind == "required" {
                if let i = reqStatus.lastIndex(of: "met") { reqStatus[i] = entry.status }
            } else if let i = prefStatus.lastIndex(of: "met") {
                prefStatus[i] = entry.status
            }
        }

        var assessments: [[String: Any]] = []
        for (i, pair) in zip(required, reqStatus).enumerated() {
            assessments.append([
                "requirement": pair.0, "kind": "required", "status": pair.1,
                "evidence": demoEvidence(pair.1, pair.0, i + jobNum, seniority)
            ])
        }
        for (i, pair) in zip(preferred, prefStatus).enumerated() {
            assessments.append([
                "requirement": pair.0, "kind": "preferred", "status": pair.1,
                "evidence": demoEvidence(pair.1, pair.0, i + jobNum + 1, seniority)
            ])
        }

        let penalty = FitScorer.requirementGaps(fromAssessments: assessments)
            .reduce(0) { $0 + FitScorer.penaltyPoints(kind: $1.kind, status: $1.status) }
        let base = Double(min(100, target + penalty))
        // Spread the dimensions around the base instead of setting them all equal — five identical
        // bars read as placeholder data. Offsets are weighted to cancel out, so the base is preserved.
        let offsets: [String: Double] = [
            "required_qualifications": 3, "preferred_qualifications": -8, "skills": 5,
            "domain_fit": -4, "experience_level": 6
        ]
        let dimensions = offsets.mapValues { min(100, max(0, base + $0)) }
        let result = FitScorer.computeScore(
            dimensions: dimensions,
            gaps: FitScorer.requirementGaps(fromAssessments: assessments),
            counts: FitScorer.requirementCounts(fromAssessments: assessments)
        )

        let dict: [String: Any] = [
            "assessment_prompt_version": FitScorer.assessmentPromptVersion,
            "overall": result.overall,
            "penalty": result.penalty,
            "summary": "Scored against \(title ?? "this role") using your resume.",
            "dimensions": FitScorer.dimensionWeights.keys.sorted().map { name in
                [
                    "name": name,
                    "score": Int(dimensions[name] ?? 0),
                    "rationale": "Derived from the requirement assessments below."
                ]
            },
            "requirement_assessments": assessments
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return (str, result.overall)
    }
}

/// Rotate the phrasing and quote the requirement back. Identical evidence on every row reads
/// as placeholder text the moment more than two rows are on screen at once.
private func demoEvidence(_ status: String, _ text: String, _ index: Int, _ seniority: String?) -> String {
    let subject = text.split(separator: " ").prefix(4).joined(separator: " ").lowercased()
    switch status {
    case "met":
        return [
            "Resume lists \(subject) directly, at \(seniority ?? "senior") level.",
            "Matched against the resume's program-management history.",
            "Covered — the resume shows this across more than one role."
        ][index % 3]
    case "partial":
        return [
            "Adjacent only: related work, but not \(subject) as described here.",
            "Partial — the resume implies this without evidencing the depth asked for."
        ][index % 2]
    default:
        return [
            "No mention of \(subject) anywhere in the resume.",
            "Not evidenced — a reader of this resume would not credit it."
        ][index % 2]
    }
}
