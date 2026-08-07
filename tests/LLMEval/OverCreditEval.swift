import XCTest
@testable import JobhuntCore

/// Behavioural regression for the named-technology evidence rule.
///
/// Assessments over-credited by mapping adjacent experience onto specifically-named technologies —
/// fuzzy semantic matching where the requirement demands literal evidence. Two verified cases:
///
///   Akamai #607    "Expertise in GPU architectures and CUDA ecosystem" → **met**, cited as
///                  "led production migration of workloads using NVIDIA H100/H200 and AMD MI350X".
///                  Running workloads on GPUs is not CUDA development.
///   Pinterest #619 "PCI/compliance" → **met**, cited as "extensive experience in regulatory
///                  compliance, including FTC consent decrees and EU DSA". Different framework,
///                  different domain.
///
/// These live in LLMEval rather than CoreTests deliberately: a unit test can only assert the prompt
/// *says* the right thing (PromptBuilderTests does that). Whether the model actually downgrades the
/// claim is behaviour, and behaviour needs a real call. Prompt wording otherwise drifts silently.
///
///   JOBHUNT_LLM_URL=http://127.0.0.1:1234 xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
final class OverCreditEval: XCTestCase {
    private struct Case {
        let name: String
        /// The requirement as extracted from the real posting.
        let requirement: String
        /// Résumé text carrying the ADJACENT evidence that was previously over-credited — and
        /// deliberately not the named technology itself.
        let resume: String
        /// The term the résumé must not be credited with.
        let namedThing: String
    }

    private static let cases: [Case] = [
        Case(
            name: "Akamai #607 — GPU migration is not CUDA expertise",
            requirement: "Expertise in GPU architectures and CUDA ecosystem",
            resume: """
            Senior Technical Program Manager. Led production migration of large training workloads
            onto NVIDIA H100 and H200 clusters and AMD MI350X, coordinating capacity, scheduling and
            rollout across infrastructure and research teams. Owned the program plan, vendor
            relationships and readiness criteria.
            """,
            namedThing: "CUDA"
        ),
        Case(
            name: "Pinterest #619 — FTC/DSA compliance is not PCI",
            requirement: "PCI compliance experience",
            resume: """
            Program leader with extensive experience in regulatory compliance, including FTC consent
            decree remediation and EU Digital Services Act readiness. Built evidence-collection
            workflows and coordinated external audits with legal and policy partners.
            """,
            namedThing: "PCI"
        )
    ]

    func testAdjacentEvidenceIsNotScoredAsMet() async throws {
        guard let config = EvalProvider.resolveConfig() else {
            throw XCTSkip(
                "No provider configured — set JOBHUNT_EVAL_PROVIDER + JOBHUNT_EVAL_MODEL "
                    + "(+ JOBHUNT_EVAL_API_KEY for a hosted provider)"
            )
        }
        let (maybeProvider, reason) = EvalProvider.make(config)
        guard let provider = maybeProvider else { throw XCTSkip(reason ?? "provider unavailable") }
        let model = config.model

        let repeats = EvalProvider.repeats()
        print("\n=== Over-credit eval (named-technology rule)\(repeats > 1 ? " x\(repeats)" : "") ===")
        var failures: [String] = []

        // Repeated for the same reason as the judgement eval: at temperature 0 these models still
        // change their minds between identical calls, so a single pass is a sample, not a verdict.
        for pass in 0 ..< repeats {
            if repeats > 1 { print("  pass \(pass + 1)/\(repeats)") }
            for testCase in Self.cases {
                // The requirement list reaches the prompt through the job's extracted JSON.
                let extracted = try JSONSerialization.data(withJSONObject: [
                    "requirements": [testCase.requirement],
                    "nice_to_have": [] as [String],
                    "skills": [] as [String]
                ])
                let job = JobFitSnapshot(
                    title: "Senior Product Manager",
                    company: "Example",
                    seniority: nil,
                    extractedJSON: String(data: extracted, encoding: .utf8),
                    extractionModel: model
                )
                let output = try await ExtractionEngine.scoreFit(
                    job: job,
                    resume: ResumeSnapshot(text: testCase.resume),
                    model: model,
                    provider: provider
                )
                guard let json = output.fitScoreJSON,
                      let data = json.data(using: .utf8),
                      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let assessments = raw["requirement_assessments"] as? [[String: Any]],
                      let assessment = assessments.first
                else {
                    failures.append("\(testCase.name): no requirement assessment returned")
                    continue
                }

                let status = (assessment["status"] as? String) ?? "?"
                let evidence = (assessment["evidence"] as? String) ?? ""
                print("  \(testCase.name)\n    status=\(status)  evidence=\(evidence)")

                if status == "met" {
                    failures.append(
                        "\(testCase.name): scored 'met' for \(testCase.namedThing) on adjacent evidence — "
                            + "the rule needs to be stronger. Evidence: \(evidence)"
                    )
                }
                // There used to be a second check here: fail if the evidence string mentions the named
                // thing while the résumé doesn't. It produced FALSE FAILURES on correct answers, because
                // the right answer names the thing in order to deny it —
                //
                //   status=partial  "…but resume does not explicitly state CUDA-specific expertise."
                //
                // That is precisely the judgement the rule is meant to produce, and the check flagged it.
                // It failed deepseek, Haiku and Ministral identically, which read as "no model handles
                // over-crediting" when in fact all three handled it correctly. A substring match cannot
                // tell an assertion from a denial, and negation detection is not worth the fragility, so
                // `status` — the field that actually drives the score — is the assertion.
            }
        }

        if !failures.isEmpty {
            XCTFail("Over-credit regressions (\(failures.count) across \(repeats) pass(es)):\n"
                + failures.joined(separator: "\n"))
        }
    }
}
