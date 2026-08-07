import Foundation
import JobhuntCore

// ScoreLab — compare scoring variants over the real corpus, without launching the app.
//
// Re-scoring is free: every analysis is stored as JSON, so a variant can be evaluated over hundreds
// of real jobs in seconds with no LLM calls. The point of this tool is that it scores through
// `FitScorer.score(_:...)` — the same code the app uses — so an experiment can't quietly diverge
// from what ships, which is exactly what happened while these comparisons lived in scratch scripts.
//
//   scorelab                       # compare variants over the live store (read-only)
//   scorelab --status Interested   # only the jobs under active evaluation
//   scorelab --json out.json       # machine-readable, for an eval to consume

struct Row {
    let jobNumber: Int
    let company: String
    let title: String
    let status: String
    let dimensions: [String: Double]
    let assessments: [[String: Any]]
}

let args = CommandLine.arguments
func flag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), args.index(after: i) < args.endIndex else { return nil }
    let v = args[args.index(after: i)]
    return v.hasPrefix("--") ? nil : v
}

// Ground truth lives outside the repo on purpose: the labels quote résumé facts, and this repo is
// public.
if let labelled = flag("--labelled") {
    try LabelledEval.run(directory: labelled, resumePath: flag("--resume"))
    exit(0)
}

let statusFilter = flag("--status")
let jsonOut = flag("--json")
let storePath = flag("--store")
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Jobhunt/jobhunt.store").path

let rows = try ScoreLabStore.load(storePath: storePath, status: statusFilter)
guard !rows.isEmpty else {
    print("No scored jobs found in \(storePath)\(statusFilter.map { " with status \($0)" } ?? "").")
    exit(1)
}

let variants: [ScoringVariant] = [
    .current,
    .verdictShare(partialCredit: 0.5),
    .hybrid(verdictWeight: 0.5, partialCredit: 0.5),
    .hybrid(verdictWeight: 0.6, partialCredit: 0.5),
    .hybrid(verdictWeight: 0.5, partialCredit: 0.25)
]

var scores: [String: [Int]] = [:]
for variant in variants {
    scores[variant.name] = rows.map {
        FitScorer.score(variant, dimensions: $0.dimensions, assessments: $0.assessments)
    }
}

let baseline = scores[ScoringVariant.current.name] ?? []
print("\(rows.count) scored jobs\(statusFilter.map { " (status: \($0))" } ?? "")\n")
print("variant                              med   >=90  40-80  top30    sd   rho")
for variant in variants {
    guard let s = scores[variant.name] else { continue }
    print(String(
        format: "%-34s %5d %5.0f%% %5.0f%% %5.0f%% %6.1f %5.3f",
        (variant.name as NSString).utf8String!,
        Stats.median(s), Stats.pct(s) { $0 >= 90 }, Stats.pct(s) { (40 ... 80).contains($0) },
        Stats.topResolution(s), Stats.sd(s), Stats.spearman(baseline, s)
    ))
}

// The user's triage question, which a blended number hides.
let missing = rows.map { FitScorer.missingRequiredCount(assessments: $0.assessments) }
print("\nmissing required qualifications: none \(missing.count { $0 == 0 }), "
    + "one \(missing.count { $0 == 1 }), two \(missing.count { $0 == 2 }), "
    + "three+ \(missing.count { $0 >= 3 })")

// Discrimination is what the top of the list needs: jobs missing a hard requirement must sit clearly
// below jobs missing none, under whichever variant is chosen.
for variant in variants {
    guard let s = scores[variant.name] else { continue }
    let clean = zip(s, missing).filter { $0.1 == 0 }.map(\.0)
    let gap = zip(s, missing).filter { $0.1 > 0 }.map(\.0)
    guard !clean.isEmpty, !gap.isEmpty else { continue }
    print(String(format: "  %-34s clean median %3d  vs  missing-required median %3d",
                 (variant.name as NSString).utf8String!, Stats.median(clean), Stats.median(gap)))
}

if let jsonOut {
    var payload: [[String: Any]] = []
    for (i, row) in rows.enumerated() {
        var entry: [String: Any] = [
            "job_number": row.jobNumber, "company": row.company, "title": row.title,
            "status": row.status, "missing_required": missing[i]
        ]
        for variant in variants { entry[variant.name] = scores[variant.name]?[i] ?? 0 }
        payload.append(entry)
    }
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: jsonOut))
    print("\nwrote \(payload.count) rows to \(jsonOut)")
}
