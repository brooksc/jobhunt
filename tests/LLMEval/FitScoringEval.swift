import XCTest
@testable import JobhuntCore

/// Benchmark for fit-scoring JUDGMENT, which nothing measured until now.
///
/// The extraction eval checks whether fields are pulled out correctly. It says nothing about whether
/// the model's requirement assessments are honest — and that judgment is what every score, filter and
/// triage decision rests on. Each case below is a real posting where the scorer was demonstrably
/// wrong, so this doubles as a regression suite for the prompt rules added to fix them.
///
/// Run against whichever model you're evaluating:
///
///     JOBHUNT_EVAL_PROVIDER=openrouter \
///     JOBHUNT_EVAL_MODEL=deepseek/deepseek-v4-flash-0731 \
///     JOBHUNT_EVAL_API_KEY=sk-or-... \
///       xcodebuild test -project Jobhunt.xcodeproj -scheme Jobhunt-DMG \
///         -destination 'platform=macOS' -only-testing:LLMEval/FitScoringEval
///
/// Reporting mode by default. Set `JOBHUNT_EVAL_STRICT=1` to fail the run on any miss, which is what
/// you want when comparing two candidate models.
final class FitScoringEval: XCTestCase {
    // MARK: - Fixtures

    private struct Case {
        let name: String
        /// Why the case exists — printed on failure so a regression explains itself.
        let rationale: String
        let jobTitle: String
        let company: String
        let requirements: [String]
        let niceToHaves: [String]
        /// Job text the model sees beyond the requirement list. Domain judgments depend on it.
        let jobContext: String
        let resume: String
        /// Requirement substring → statuses that are acceptable.
        let expectedStatuses: [(needle: String, allowed: Set<String>)]
        /// Requirements that must not be assessed at all (no candidate could fail them).
        let expectedOmitted: [String]
        /// Inclusive bound on domain_fit, when the case is about domain judgment.
        let maxDomainFit: Int?
    }

    /// A résumé stub in the shape of the real master: software/AI-infrastructure program leadership,
    /// no hardware engineering, no CUDA development, no named PM tooling.
    private static let resume = """
    Senior Technical Program Manager — 20+ years in software and platform program leadership.
    Led production migration of large training workloads onto NVIDIA H100/H200 and AMD MI350X
    clusters, coordinating capacity, scheduling and rollout across infrastructure and research teams.
    Founded an API governance program; managed FTC consent-decree remediation and EU Digital Services
    Act readiness. Earlier: DRM conformance testing, carrier certification for mobile integrations,
    embedded media work on ARM and TI DSP platforms. B.S. Computer Science. PMP certified.
    Strong written and verbal communication; influences engineering and product leadership without
    formal authority.
    """

    private static let cases: [Case] = [
        Case(
            name: "#607 Akamai — GPU migration is not CUDA expertise",
            rationale: "Scored met citing an H100/H200 migration. Running workloads on GPUs is not "
                + "CUDA development; the résumé never names CUDA.",
            jobTitle: "Senior Product Manager, Compute Infrastructure",
            company: "Akamai",
            requirements: ["Expertise in GPU architectures and CUDA ecosystem"],
            niceToHaves: [],
            jobContext: "Own the GPU compute product line: instance types, scheduling, and the CUDA "
                + "developer experience for customers running training and inference workloads.",
            resume: resume,
            expectedStatuses: [(needle: "CUDA", allowed: ["partial", "missing"])],
            expectedOmitted: [],
            maxDomainFit: nil
        ),
        Case(
            name: "#231 Mainspring — software background is not hardware/controls",
            rationale: "Scored met by reaching into the parenthetical for 'software', in a posting "
                + "about manufacturing linear generators. domain_fit also scored 90.",
            jobTitle: "Staff Technical Program Manager",
            company: "Mainspring Energy",
            requirements: [
                "Background in hardware or controls engineering (electrical, software, mechanical, "
                    + "or systems) or equivalent experience enabling effective partnership with technical teams"
            ],
            niceToHaves: [],
            jobContext: "Mainspring builds linear generators. Drive new product introduction for the "
                + "generator platform: design validation, manufacturing scale-up, supplier "
                + "qualification, production ramp and field reliability across mechanical, "
                + "electrical and controls teams.",
            resume: resume,
            expectedStatuses: [(needle: "hardware or controls", allowed: ["partial", "missing"])],
            expectedOmitted: [],
            maxDomainFit: 70
        ),
        Case(
            name: "#718 Akamai — 'capacity to learn' is not a gap",
            rationale: "Cost 6 points and appeared under Gaps. Satisfied by anyone; the gap was "
                + "manufactured by the named-technology rule because the résumé omits JIRA.",
            jobTitle: "Senior Technical Program Manager",
            company: "Akamai",
            requirements: ["Experience with, or capacity to learn, JIRA, Confluence, and Aha"],
            niceToHaves: [],
            jobContext: "Run delivery for platform programs; maintain plans and dependencies.",
            resume: resume,
            expectedStatuses: [],
            expectedOmitted: ["JIRA"],
            maxDomainFit: nil
        ),
        Case(
            name: "values alignment is not assessable",
            rationale: "A résumé cannot evidence it and the posting never defines it, so grading it "
                + "invents a gap the candidate cannot close.",
            jobTitle: "Staff Technical Program Manager",
            company: "Zip",
            requirements: ["10+ years in program management", "Alignment with Zip's core values"],
            niceToHaves: [],
            jobContext: "Lead cross-functional programs across the payments platform.",
            resume: resume,
            expectedStatuses: [(needle: "10+ years", allowed: ["met"])],
            expectedOmitted: ["core values"],
            maxDomainFit: nil
        ),
        Case(
            name: "#619 Pinterest — a one-or-more list is satisfied by any option",
            rationale: "The posting asks for 'one or more of the following' as a PREFERRED list, so "
                + "compliance experience genuinely satisfies it. Marking it missing would be wrong.",
            jobTitle: "Technical Program Manager, Security",
            company: "Pinterest",
            requirements: ["5+ years of information security, risk and/or compliance experience"],
            niceToHaves: [
                "Experience in one or more of: security programs, abuse/anti-automation, fraud, "
                    + "account security, PCI/compliance, vulnerability management, business continuity"
            ],
            jobContext: "Drive security and compliance programs across the platform.",
            resume: resume,
            expectedStatuses: [(needle: "one or more", allowed: ["met", "partial"])],
            expectedOmitted: [],
            maxDomainFit: nil
        )
    ]

    // MARK: - Run

    func testFitScoringJudgment() async throws {
        guard let config = EvalProvider.resolveConfig() else {
            throw XCTSkip(
                "No provider configured — set JOBHUNT_EVAL_PROVIDER + JOBHUNT_EVAL_MODEL "
                    + "(+ JOBHUNT_EVAL_API_KEY for a hosted provider)"
            )
        }
        let (maybeProvider, reason) = EvalProvider.make(config)
        guard let provider = maybeProvider else { throw XCTSkip(reason ?? "provider unavailable") }
        let strict = ProcessInfo.processInfo.environment["JOBHUNT_EVAL_STRICT"] == "1"

        print("\n=== Fit-scoring judgment eval ===")
        print("Provider: \(config.provider)   Model: \(config.model)")
        print("Prompt version: \(FitScorer.assessmentPromptVersion)\n")

        var checks = 0
        var passed = 0
        var failures: [String] = []

        for testCase in Self.cases {
            let extracted: [String: Any] = [
                "requirements": testCase.requirements,
                "nice_to_have": testCase.niceToHaves,
                "skills": [] as [String],
                "summary": testCase.jobContext
            ]
            let json = (try? JSONSerialization.data(withJSONObject: extracted))
                .flatMap { String(data: $0, encoding: .utf8) }
            let job = JobFitSnapshot(
                title: testCase.jobTitle, company: testCase.company, seniority: nil,
                extractedJSON: json, extractionModel: config.model
            )

            let output: FitScoreOutput
            do {
                output = try await ExtractionEngine.scoreFit(
                    job: job, resume: ResumeSnapshot(text: testCase.resume),
                    model: config.model, provider: provider
                )
            } catch {
                failures.append("\(testCase.name): scoring threw — \(error)")
                continue
            }

            guard let raw = output.fitScoreJSON?.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                failures.append("\(testCase.name): unparseable response")
                continue
            }
            let assessments = (dict["requirement_assessments"] as? [[String: Any]]) ?? []
            let dimensions = (dict["dimensions"] as? [[String: Any]]) ?? []
            print("  \(testCase.name)  → score \(output.score.overall)")

            for expectation in testCase.expectedStatuses {
                checks += 1
                let match = assessments.first {
                    (($0["requirement"] as? String) ?? "").localizedCaseInsensitiveContains(expectation.needle)
                }
                let status = (match?["status"] as? String) ?? "<absent>"
                if expectation.allowed.contains(status) {
                    passed += 1
                } else {
                    failures.append(
                        "\(testCase.name)\n      '\(expectation.needle)' → \(status), "
                            + "expected one of \(expectation.allowed.sorted())\n      why: \(testCase.rationale)"
                    )
                }
                print("      '\(expectation.needle)' → \(status)")
            }

            for omitted in testCase.expectedOmitted {
                checks += 1
                let present = assessments.contains {
                    (($0["requirement"] as? String) ?? "").localizedCaseInsensitiveContains(omitted)
                }
                // The deterministic filter drops these before they can cost anything, so the check
                // that matters is that they contribute no penalty — not that the model omitted them.
                let gaps = FitScorer.requirementGaps(fromAssessments: assessments)
                let penalised = gaps.contains { $0.requirement.localizedCaseInsensitiveContains(omitted) }
                if penalised {
                    failures.append(
                        "\(testCase.name)\n      '\(omitted)' was penalised\n      why: \(testCase.rationale)"
                    )
                } else {
                    passed += 1
                }
                print("      '\(omitted)' assessed=\(present) penalised=\(penalised)")
            }

            if let maxDomain = testCase.maxDomainFit {
                checks += 1
                let score = dimensions.first { ($0["name"] as? String) == "domain_fit" }
                    .flatMap { $0["score"] as? Int } ?? 100
                if score <= maxDomain {
                    passed += 1
                } else {
                    failures.append(
                        "\(testCase.name)\n      domain_fit \(score) > \(maxDomain)\n      why: \(testCase.rationale)"
                    )
                }
                print("      domain_fit \(score) (max \(maxDomain))")
            }
        }

        let pct = checks > 0 ? Int(Double(passed) / Double(checks) * 100) : 0
        print("\n=== \(passed)/\(checks) checks passed (\(pct)%) ===")
        if !failures.isEmpty {
            print("\nMisses:\n" + failures.joined(separator: "\n"))
        }
        if strict, !failures.isEmpty {
            XCTFail("Fit-scoring eval: \(checks - passed)/\(checks) checks failed")
        }
    }
}
