import Foundation
import JobhuntCore

// Evaluation against hand-labelled ground truth.
//
// The corpus tells us how scores are *distributed*; only labels tell us which scores are *right*.
// The labels come from the résumé agent's per-requirement judgements
// (`~/Desktop/resume/fitscore-collab/labelled/job-*.json`).
//
// **Only the per-requirement verdicts are used.** The same collaboration established that the
// labeller's hand-set overall bands are anchored to the model's own output — every corpus dump put
// `current_score` in header position — so band-level targets are contaminated and a calibration
// measured against them is circular. Verdicts were set against résumé facts and stand.
//
// The target therefore holds the model's dimension numbers fixed and substitutes ground-truth
// verdicts. That isolates exactly what a requirement filter can affect: the penalty term. Any
// remaining error is dimension error, which no filter here touches.

struct LabelledJob {
    let jobNumber: Int
    let title: String
    let dimensions: [String: Double]
    /// What the model said.
    let modelAssessments: [[String: Any]]
    /// The same requirements, with the labeller's verdict substituted.
    let truthAssessments: [[String: Any]]

    static func load(directory: String) throws -> [LabelledJob] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: directory)
            .filter { $0.hasPrefix("job-") && $0.hasSuffix(".json") }.sorted()
        return try files.compactMap { name -> LabelledJob? in
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  let number = root["job_number"] as? Int,
                  let assessments = root["requirement_assessments"] as? [[String: Any]],
                  let truth = root["ground_truth"] as? [String: Any],
                  let verdicts = truth["requirement_verdicts"] as? [[String: Any]]
            else { return nil }

            var dimensions: [String: Double] = [:]
            for d in (root["dimensions"] as? [[String: Any]]) ?? [] {
                if let n = d["name"] as? String, let v = d["score"] as? Double { dimensions[n] = v }
                else if let n = d["name"] as? String, let v = d["score"] as? Int { dimensions[n] = Double(v) }
            }

            // Verdicts carry the index of the assessment they judge; anything unlabelled keeps the
            // model's answer rather than being dropped, so both sides score the same requirement set.
            var truthAssessments = assessments
            for v in verdicts {
                guard let i = v["index"] as? Int, i < truthAssessments.count,
                      let status = v["ground_truth_status"] as? String else { continue }
                truthAssessments[i]["status"] = status
            }
            return LabelledJob(
                jobNumber: number,
                title: (root["title"] as? String) ?? "",
                dimensions: dimensions,
                modelAssessments: assessments,
                truthAssessments: truthAssessments
            )
        }
    }
}

enum LabelledEval {
    /// How close a candidate ranking gets to the ground-truth one.
    struct Result {
        let name: String
        let mae: Double
        let rho: Double
        /// Overlap between the candidate's best five jobs and ground truth's. The user's stated
        /// primary criterion: they triage from the top of the list.
        let topFive: Int
        let scores: [Int]
    }

    static func run(directory: String, resumePath: String?) throws {
        let jobs = try LabelledJob.load(directory: directory)
        guard !jobs.isEmpty else {
            print("No labelled jobs in \(directory)")
            exit(1)
        }

        // Target: ground-truth verdicts, taken at face value — the fragment filter is deliberately
        // NOT applied here. Applying it to both sides would let the filter grade its own homework.
        let target = jobs.map {
            FitScorer.score(
                .current, dimensions: $0.dimensions, assessments: $0.truthAssessments, exclusions: .nonDiscriminating
            )
        }

        let candidates: [(String, FitScorer.Exclusions)] = [
            ("no filters", .none),
            ("non-discriminating only (shipped before)", .nonDiscriminating),
            ("+ fragment filter (shipped now)", .all)
        ]

        print("\(jobs.count) labelled jobs · target = shipped arithmetic over ground-truth verdicts\n")
        print("candidate                                   MAE    rho  top5")
        var results: [Result] = []
        for (name, exclusions) in candidates {
            let s = jobs.map {
                FitScorer.score(
                    .current, dimensions: $0.dimensions, assessments: $0.modelAssessments,
                    exclusions: exclusions
                )
            }
            let r = Result(
                name: name,
                mae: Stats.mae(s, target),
                rho: Stats.spearman(s, target),
                topFive: Stats.topOverlap(s, target, n: 5),
                scores: s
            )
            results.append(r)
            print(String(format: "%-40s %6.1f %6.3f  %d/5", (name as NSString).utf8String!, r.mae, r.rho, r.topFive))
        }

        // Sensitivity: does the verdict hold if the labeller's fragment verdicts are dropped too?
        let filteredTarget = jobs.map {
            FitScorer.score(
                .current, dimensions: $0.dimensions, assessments: $0.truthAssessments, exclusions: .all
            )
        }
        print("\nsame, against a target that also drops fragments:")
        for (name, exclusions) in candidates {
            let s = jobs.map {
                FitScorer.score(
                    .current, dimensions: $0.dimensions, assessments: $0.modelAssessments,
                    exclusions: exclusions
                )
            }
            print(String(
                format: "%-40s %6.1f %6.3f  %d/5", (name as NSString).utf8String!,
                Stats.mae(s, filteredTarget),
                Stats.spearman(s, filteredTarget),
                Stats.topOverlap(s, filteredTarget, n: 5)
            ))
        }

        // How much of the corpus the filter actually touches, so a null result can be told apart
        // from a filter that simply never fired.
        var fragments = 0, total = 0
        for job in jobs {
            for a in job.modelAssessments {
                guard let r = a["requirement"] as? String else { continue }
                total += 1
                if FitScorer.isFragment(requirement: r) { fragments += 1 }
            }
        }
        print(String(format: "\nfragments: %d of %d assessments (%.1f%%)",
                     fragments, total, 100 * Double(fragments) / Double(max(total, 1))))

        if let resumePath {
            try reportEvidence(jobs: jobs, directory: directory, resumePath: resumePath)
        }

        print("\njob   title                                     truth  before  after")
        for (i, job) in jobs.enumerated() {
            let title = String(job.title.prefix(40))
            print(String(format: "%-5d %-42s %5d %6d %6d",
                         job.jobNumber, (title as NSString).utf8String!,
                         target[i], results[1].scores[i], results[2].scores[i]))
        }
    }

    /// Does the Swift port of the fabricated-evidence check reproduce the Python measurement?
    ///
    /// The corpus pass measured 32% of quoted spans unsupported, 74% of those lifted from the
    /// posting; the résumé agent independently measured 35% on these same 20 jobs. If this column
    /// disagrees, the shipped check is not the thing that was measured.
    static func reportEvidence(jobs: [LabelledJob], directory: String, resumePath: String) throws {
        let resume = try String(contentsOfFile: resumePath, encoding: .utf8)
        var quoted = 0, lifted = 0, invented = 0, onMet = 0
        for job in jobs {
            let posting = postingText(directory: directory, jobNumber: job.jobNumber)
            for a in job.modelAssessments {
                let evidence = (a["evidence"] as? String) ?? ""
                quoted += EvidenceCheck.quotedSpans(in: evidence).count
                for span in EvidenceCheck.unsupported(
                    evidence: evidence, resumes: [resume], posting: posting
                ) {
                    if span.support == .liftedFromPosting { lifted += 1 } else { invented += 1 }
                    if (a["status"] as? String) == "met" { onMet += 1 }
                }
            }
        }
        let bad = lifted + invented
        print(String(
            format: "\nevidence: %d quoted spans, %d unsupported (%.0f%%) — %d lifted from the posting "
                + "(%.0f%% of those), %d invented; %d sit on a `met`",
            quoted, bad, 100 * Double(bad) / Double(max(quoted, 1)),
            lifted, 100 * Double(lifted) / Double(max(bad, 1)), invented, onMet
        ))
    }

    private static func postingText(directory: String, jobNumber: Int) -> String {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("job-\(jobNumber).json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }
        return (root["job_description"] as? String) ?? ""
    }
}
