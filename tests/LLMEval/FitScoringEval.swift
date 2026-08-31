import XCTest
@testable import JobhuntCore

/// Benchmark for fit-scoring JUDGMENT, which nothing measured until now.
///
/// The extraction eval checks whether fields are pulled out correctly. It says nothing about whether
/// the model's requirement assessments are honest — and that judgment is what every score, filter and
/// triage decision rests on. Each case below is a real posting where the scorer was demonstrably
/// wrong, so this doubles as a regression suite for the prompt rules added to fix them.
///
/// Runs every model listed in `~/.config/jobhunt/eval-models` against identical fixtures and prints
/// a comparison. Comparing in ONE run matters: this scorer's run-to-run variance has been measured at
/// 23 points on identical input, so a difference seen across separate runs of separate models means
/// very little.
///
/// Reporting mode by default. `JOBHUNT_EVAL_STRICT=1` fails the run if the best model still misses.
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
        /// Requirement substring → statuses that are acceptable.
        let expectedStatuses: [(needle: String, allowed: Set<String>)]
        /// Requirements that must not be assessed at all (no candidate could fail them).
        let expectedOmitted: [String]
        /// Inclusive bound on domain_fit, when the case is about domain judgment.
        let maxDomainFit: Int?
    }

    /// Fallback résumé, used when no real one is configured. Shaped like the master —
    /// software/AI-infrastructure program leadership, no hardware engineering, no CUDA development,
    /// no named PM tooling — because every expectation below depends on those absences.
    private static let fallbackResume = """
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
            expectedStatuses: [(needle: "one or more", allowed: ["met", "partial"])],
            expectedOmitted: [],
            maxDomainFit: nil
        )
    ]

    // MARK: - Run

    private struct Result {
        let model: String
        var checks = 0
        var passed = 0
        var failures: [String] = []
        var scores: [String: Int] = [:]
        var error: String?
    }

    func testFitScoringJudgment() async throws {
        let configs = EvalProvider.resolveConfigs()
        guard !configs.isEmpty else {
            throw XCTSkip(
                "No model configured — write one per line to ~/.config/jobhunt/eval-models "
                    + "(or a single ~/.config/jobhunt/eval-model), plus eval-provider and eval-api-key"
            )
        }
        let (resumeText, isRealResume) = EvalProvider.resume(fallback: Self.fallbackResume)
        let strict = ProcessInfo.processInfo.environment["JOBHUNT_EVAL_STRICT"] == "1"

        print("\n=== Fit-scoring judgment eval ===")
        print("Prompt version: \(FitScorer.assessmentPromptVersion)")
        print("Résumé: \(isRealResume ? "real (~/.config/jobhunt/eval-resume.md)" : "synthetic fallback")"
            + " — \(resumeText.count) chars")
        print("Models: \(configs.map(\.model).joined(separator: ", "))\n")

        var results: [Result] = []
        for config in configs {
            var result = Result(model: "\(config.provider):\(config.model)")
            let (maybeProvider, reason) = EvalProvider.make(config)
            guard let provider = maybeProvider else {
                result.error = reason
                results.append(result)
                print("  \(result.model): SKIPPED — \(reason ?? "unavailable")")
                continue
            }
            let repeats = EvalProvider.repeats()
            print("  --- \(result.model)\(repeats > 1 ? " (x\(repeats))" : "") ---")
            // Repeat the whole fixture set: hosted inference is not deterministic at temperature 0,
            // so one pass measures a sample, not a model. `checks`/`passed` accumulate across repeats,
            // which turns the report into a pass RATE.
            for _ in 0 ..< repeats {
                for testCase in Self.cases {
                    await run(
                        testCase,
                        provider: provider,
                        model: config.model,
                        resume: resumeText,
                        into: &result
                    )
                }
            }
            results.append(result)
        }

        report(results)

        let best = results.filter { $0.error == nil }.map { $0.checks - $0.passed }.min()
        if strict, let best, best > 0 {
            XCTFail("Fit-scoring eval: the best model still missed \(best) check(s)")
        }
        if results.allSatisfy({ $0.error != nil }) {
            throw XCTSkip(results.compactMap(\.error).joined(separator: "; "))
        }
    }

    private func run(
        _ testCase: Case,
        provider: any LLMProvider,
        model: String,
        resume: String,
        into result: inout Result
    ) async {
        let extracted: [String: Any] = [
            "requirements": testCase.requirements,
            "nice_to_haves": testCase.niceToHaves,
            "skills": [] as [String],
            "summary": testCase.jobContext
        ]
        let json = (try? JSONSerialization.data(withJSONObject: extracted))
            .flatMap { String(data: $0, encoding: .utf8) }
        let job = JobFitSnapshot(
            title: testCase.jobTitle, company: testCase.company, seniority: nil,
            extractedJSON: json, extractionModel: model
        )

        let output: FitScoreOutput
        do {
            output = try await ExtractionEngine.scoreFit(
                job: job, resume: ResumeSnapshot(text: resume), model: model, provider: provider,
                feedback: []
            )
        } catch {
            result.failures.append("\(testCase.name): scoring threw — \(error)")
            result.checks += 1
            return
        }

        guard let raw = output.fitScoreJSON?.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            result.failures.append("\(testCase.name): unparseable response")
            result.checks += 1
            return
        }
        let assessments = (dict["requirement_assessments"] as? [[String: Any]]) ?? []
        let dimensions = (dict["dimensions"] as? [[String: Any]]) ?? []
        result.scores[testCase.name] = output.score.overall
        print("    \(testCase.name) → \(output.score.overall)")

        for expectation in testCase.expectedStatuses {
            result.checks += 1
            let match = assessments.first {
                (($0["requirement"] as? String) ?? "").localizedCaseInsensitiveContains(expectation.needle)
            }
            let status = (match?["status"] as? String) ?? "<absent>"
            if expectation.allowed.contains(status) {
                result.passed += 1
            } else {
                result.failures.append(
                    "\(testCase.name): '\(expectation.needle)' → \(status), expected "
                        + "\(expectation.allowed.sorted()) — \(testCase.rationale)"
                )
            }
            print("       '\(expectation.needle)' → \(status)")
        }

        for omitted in testCase.expectedOmitted {
            result.checks += 1
            // The deterministic filter drops these before they cost anything, so what matters is
            // that they contribute no penalty — not whether the model chose to omit them.
            let gaps = FitScorer.requirementGaps(fromAssessments: assessments)
            if gaps.contains(where: { $0.requirement.localizedCaseInsensitiveContains(omitted) }) {
                result.failures.append("\(testCase.name): '\(omitted)' was penalised — \(testCase.rationale)")
            } else {
                result.passed += 1
            }
        }

        if let maxDomain = testCase.maxDomainFit {
            result.checks += 1
            let score = dimensions.first { ($0["name"] as? String) == "domain_fit" }
                .flatMap { $0["score"] as? Int } ?? 100
            if score <= maxDomain {
                result.passed += 1
            } else {
                result.failures.append(
                    "\(testCase.name): domain_fit \(score) > \(maxDomain) — \(testCase.rationale)"
                )
            }
            print("       domain_fit \(score) (max \(maxDomain))")
        }
    }

    /// Side-by-side, because the useful question is which model is better on identical fixtures —
    /// not whether one clears an absolute bar.
    private func report(_ results: [Result]) {
        print("\n=== Comparison ===")
        let width = max(24, results.map(\.model.count).max() ?? 24)
        print("\("model".padding(toLength: width, withPad: " ", startingAt: 0))  checks   scores")
        for r in results.sorted(by: { ($0.checks - $0.passed) < ($1.checks - $1.passed) }) {
            let name = r.model.padding(toLength: width, withPad: " ", startingAt: 0)
            if let error = r.error {
                print("\(name)  SKIPPED  \(error)")
                continue
            }
            let pct = r.checks > 0 ? Int(Double(r.passed) / Double(r.checks) * 100) : 0
            let scores = Self.cases.map { r.scores[$0.name].map(String.init) ?? "-" }.joined(separator: " ")
            print("\(name)  \(r.passed)/\(r.checks) (\(pct)%)  \(scores)")
        }
        print("\nscore columns, in order:")
        for (i, c) in Self.cases.enumerated() {
            print("  \(i + 1). \(c.name)")
        }

        for r in results where !r.failures.isEmpty {
            print("\n--- \(r.model) misses ---")
            for f in r.failures {
                print("  • \(f)")
            }
        }
    }
}
