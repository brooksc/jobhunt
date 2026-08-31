import Foundation
import XCTest
@testable import JobhuntCore

/// Measures whether a model answers the same way twice, which the other evals do not.
///
/// `FitScoringEval` and `OverCreditEval` measure whether an answer is *right*. Neither says whether
/// it is *stable*, and instability caps everything else: if the score moves 12 points between
/// identical calls, then ranking work is tuning inside the noise and a "the top 5 improved" result
/// cannot be distinguished from a reroll.
///
/// Observed during the v1.4.0 walkthrough recordings: the same Reddit posting, the same résumé, the
/// same model at temperature 0, scored 41, 43, 45, 47, 51 and 53 across six takes — with the capture
/// reporting an identical 13,334 visible characters each time. `marketing/help/which-model.html`
/// tells users Ministral moves about 1.5 points. This test exists to replace six ad-hoc samples with
/// a controlled measurement.
///
/// Run:
///
///     TEST_RUNNER_JOBHUNT_EVAL_MODEL=openrouter:mistralai/ministral-14b-2512 \
///     TEST_RUNNER_JOBHUNT_EVAL_REPEATS=8 \
///       xcodebuild test -scheme Jobhunt-Eval -only-testing:LLMEval/ConsistencyEval
///
/// The `TEST_RUNNER_` prefix is mandatory — see `EvalProvider`.
final class ConsistencyEval: XCTestCase {
    /// One realistic posting, scored repeatedly. Deliberately a single fixture: the question is
    /// variance between identical calls, so holding the input fixed is the whole design.
    private static let requirements = [
        "14+ years of experience in technical program management, engineering, infrastructure, "
            + "developer tools, platform engineering, or AI tooling",
        "Experience leading multi-year, multi-organization technical programs with executive "
            + "visibility and ambiguous ownership",
        "Deep fluency in developer productivity systems (CI/CD, code review, testing, deployment, "
            + "observability, developer environments, internal platforms)",
        "Understanding of AI and LLM-enabled software development beyond personal productivity",
        "Highly data-driven with skepticism of shallow metrics",
        "Exceptional cross-functional operator and communicator",
        "Experience leading meaningful organizational change"
    ]

    private static let fallbackResume = """
    Principal Technical Program Manager with 12 years leading platform and developer-productivity
    programs. Ran a multi-year Kubernetes migration across 14 teams reporting to a VP of Engineering.
    Built program infrastructure and reduced API review cycle time from 92 days to 5. Introduced OKRs
    and quarterly planning across a 220-engineer organisation. Known for written communication that
    executives actually read.
    """

    func testScoreAndVerdictStabilityAcrossIdenticalCalls() async throws {
        guard let config = EvalProvider.resolveConfig() else {
            throw XCTSkip("No provider configured — see EvalProvider for the TEST_RUNNER_ variables.")
        }
        let (maybeProvider, reason) = EvalProvider.make(config)
        guard let provider = maybeProvider else { throw XCTSkip(reason ?? "provider unavailable") }

        let repeats = max(EvalProvider.repeats(), 2)
        let (resumeText, isRealResume) = EvalProvider.resume(fallback: Self.fallbackResume)

        print("\n=== Consistency eval x\(repeats) — \(config.model) ===")
        print("Résumé: \(isRealResume ? "real" : "synthetic fallback") — \(resumeText.count) chars")

        let extracted = try JSONSerialization.data(withJSONObject: [
            "requirements": Self.requirements,
            "nice_to_have": [] as [String],
            "skills": [] as [String]
        ])
        let job = JobFitSnapshot(
            title: "Principal Technical Program Manager, Developer Productivity",
            company: "Reddit",
            seniority: "principal",
            extractedJSON: String(data: extracted, encoding: .utf8),
            extractionModel: config.model
        )

        var scores: [Int] = []
        // requirement text -> the statuses it received across runs
        var verdicts: [String: [String]] = [:]

        // A pass that errors is DATA, not a reason to abandon the measurement: a provider that
        // returns a null `content` on one call in eight is inconsistent in the way this test exists to
        // measure, and aborting would have thrown that finding away. (It happened on the first run.)
        var failedPasses: [String] = []

        for pass in 0 ..< repeats {
            let output: FitScoreOutput
            do {
                output = try await ExtractionEngine.scoreFit(
                    job: job, resume: ResumeSnapshot(text: resumeText),
                    model: config.model, provider: provider, feedback: []
                )
            } catch {
                failedPasses.append("pass \(pass + 1): \(error)")
                print("  pass \(pass + 1)/\(repeats): FAILED — \(error)")
                continue
            }
            scores.append(output.score.overall)

            if let json = output.fitScoreJSON,
               let data = json.data(using: .utf8),
               let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let assessments = raw["requirement_assessments"] as? [[String: Any]] {
                for a in assessments {
                    guard let req = a["requirement"] as? String else { continue }
                    verdicts[req, default: []].append((a["status"] as? String) ?? "?")
                }
            }
            print("  pass \(pass + 1)/\(repeats): score=\(output.score.overall)")
        }

        guard !scores.isEmpty else {
            XCTFail("every pass failed:\n" + failedPasses.joined(separator: "\n"))
            return
        }

        // Score spread. `sd` is the population standard deviation over the repeats.
        let mean = Double(scores.reduce(0, +)) / Double(scores.count)
        let sd = (scores.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(scores.count)).squareRoot()
        let spread = (scores.max() ?? 0) - (scores.min() ?? 0)

        // A requirement is "unstable" when it did not receive the same status every time. This is the
        // number that matters most: the score is a function of these, so flipping verdicts are the
        // mechanism behind a moving score.
        // Compare against the number of SUCCESSFUL passes, not the requested repeats. Filtering on
        // `repeats` silently dropped every requirement when any pass failed, and the run reported
        // "0 of 0 requirements changed answer" — which reads as perfect stability and is the exact
        // opposite of what the data said.
        let judged = verdicts.filter { $0.value.count == scores.count }
        let unstable = judged.filter { Set($0.value).count > 1 }

        print("""

        score:    \(scores.map(String.init).joined(separator: ", "))
        mean:     \(String(format: "%.1f", mean))
        sd:       \(String(format: "%.1f", sd))
        spread:   \(spread) points (max - min)
        verdicts: \(unstable.count) of \(judged.count) requirements changed answer across \(scores.count) runs
        failed:   \(failedPasses.count) of \(repeats) passes returned no usable response
        """)
        for (req, statuses) in unstable.sorted(by: { $0.key < $1.key }) {
            print("  flip: \(statuses.joined(separator: " → "))  \(req.prefix(70))")
        }

        // Recorded, not enforced. A threshold here would be a guess at what "consistent enough" means
        // before we know what any model achieves, and a failing eval nobody can act on gets muted.
        // The decision this feeds is in TASK-661; the numbers above are the deliverable.
        XCTAssertFalse(scores.isEmpty, "the measurement needs at least one usable response")
    }
}
