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
        guard let providerURL = ProcessInfo.processInfo.environment["JOBHUNT_LLM_URL"] else {
            throw XCTSkip("No LLM provider configured — set JOBHUNT_LLM_URL to run this eval")
        }
        guard let model = ProcessInfo.processInfo.environment["JOBHUNT_LLM_MODEL"] else {
            throw XCTSkip("No model configured — set JOBHUNT_LLM_MODEL to run this eval")
        }
        let provider = LMStudioProvider(baseURL: providerURL, model: model)

        print("\n=== Over-credit eval (named-technology rule) ===")
        var failures: [String] = []

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
            // The evidence string must not claim the named thing the résumé never mentions.
            if evidence.localizedCaseInsensitiveContains(testCase.namedThing),
               !testCase.resume.localizedCaseInsensitiveContains(testCase.namedThing) {
                failures.append(
                    "\(testCase.name): evidence asserts \(testCase.namedThing), which the résumé never states"
                )
            }
        }

        if !failures.isEmpty {
            XCTFail("Over-credit regressions:\n" + failures.joined(separator: "\n"))
        }
    }
}
