import XCTest
@testable import JobhuntCore

// MARK: - LLMEvalHarness

// swiftlint:disable type_body_length
/// Eval harness for LLM extraction accuracy.
///
/// Run with a local provider:
///   JOBHUNT_LLM_URL=http://127.0.0.1:1234 xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
///
/// The test skips gracefully when no provider is configured.
/// It prints a field-by-field accuracy report but does NOT fail on low accuracy.
final class LLMEvalHarness: XCTestCase {
    // MARK: - Fixtures

    /// Synthetic extraction fixtures ported from tests/llm-eval/eval-llm.js.
    private struct ExtractionFixture {
        let name: String
        let description: String
        let url: String
        let pageTitle: String
        // Expected field values (nil = not asserted)
        let expectedCompany: String?
        let expectedTitleContains: String?
        let expectedRemoteType: String?
        let expectedSalaryMin: Int?
        let expectedSalaryMax: Int?
        let expectedSalaryCurrency: String?
        let expectedSkillsAny: [String]
        let expectedRequirementsAny: [String]
    }

    private static let fixtures: [ExtractionFixture] = [
        ExtractionFixture(
            name: "remote salary bands and application URL",
            description: """
            ExampleCloud
            Principal Technical Program Manager, AI Platform
            Remote - United States
            Full-time
            Senior level

            This role is fully remote within the United States. You will lead cross-functional delivery for
            LLM inference, API reliability, eval pipelines, and developer productivity programs.

            Required qualifications:
            - 8+ years of technical program management experience.
            - Experience leading cloud infrastructure, distributed systems, or AI platform programs.
            - Strong executive communication and cross-functional planning.

            Preferred qualifications:
            - Experience with LLM platforms, model evaluation, or developer tooling.
            - Experience defining reliability metrics and operational reviews.

            Salary range: $185,000 - $245,000 USD base salary. San Francisco and New York range:
            $210,000 - $285,000 USD.

            Apply at https://jobs.example.com/apply/platform-tpm
            """,
            url: "https://jobs.example.com/platform-tpm",
            pageTitle: "Principal Technical Program Manager, AI Platform - ExampleCloud Careers",
            expectedCompany: "ExampleCloud",
            expectedTitleContains: "Technical Program Manager",
            expectedRemoteType: "remote",
            expectedSalaryMin: 185_000,
            expectedSalaryMax: 285_000,
            expectedSalaryCurrency: "USD",
            expectedSkillsAny: ["LLM", "AI", "developer", "distributed"],
            expectedRequirementsAny: ["8+", "technical program management", "cloud", "AI"]
        ),
        ExtractionFixture(
            name: "hybrid location and contract employment",
            description: """
            PayWorks
            Technical Program Manager, Payments
            Seattle, WA
            Work site: 3 days/week in-office
            Contract

            The Payments team needs a Technical Program Manager to coordinate partner integrations,
            launch readiness, risk tracking, and incident follow-up for payment processing systems.

            Must have:
            - 5+ years technical program management experience.
            - Payment systems or fintech experience.
            - Ability to manage vendor dependencies and launch plans.

            Nice to have:
            - SQL familiarity.
            - Experience with fraud or risk systems.

            Pay: $85/hr - $105/hr on W2 contract.
            """,
            url: "https://careers.example.org/jobs/123",
            pageTitle: "Technical Program Manager, Payments",
            expectedCompany: "PayWorks",
            expectedTitleContains: "Technical Program Manager",
            expectedRemoteType: "hybrid",
            expectedSalaryMin: nil, // hourly conversion varies by normalizer
            expectedSalaryMax: nil,
            expectedSalaryCurrency: "USD",
            expectedSkillsAny: ["payments", "fintech", "vendor", "launch", "risk", "SQL"],
            expectedRequirementsAny: ["5+", "payment", "fintech", "vendor", "launch"]
        ),
        ExtractionFixture(
            name: "Microsoft remote role US pay band",
            description: """
            Microsoft
            Senior Product Manager
            United States, Multiple Locations, Multiple Locations
            Work site 0 days / week in-office - remote
            Full-Time

            Product Management IC4 - The typical base pay range for this role across the U.S. is
            USD $119,800 - $234,700 per year. There is a different range applicable to specific
            work locations, within the San Francisco Bay area and New York City metropolitan area,
            and the base pay range for this role in those locations is USD $158,400 - $258,000 per year.

            Responsibilities:
            - Drive product strategy and execution across Microsoft 365 experiences.
            - Partner with engineering, design, and research teams.

            Required qualifications:
            - 4+ years product or technical program management experience.
            - Experience managing cross-functional product delivery.
            """,
            url: "https://apply.careers.microsoft.com/careers?pid=fixture-ms-product",
            pageTitle: "Senior Product Manager | Microsoft Careers",
            expectedCompany: "Microsoft",
            expectedTitleContains: "Product Manager",
            expectedRemoteType: "remote",
            expectedSalaryMin: 119_800,
            expectedSalaryMax: 234_700,
            expectedSalaryCurrency: "USD",
            expectedSkillsAny: ["product strategy", "cross-functional", "product delivery"],
            expectedRequirementsAny: ["4+", "product", "technical program management", "cross-functional"]
        )
    ]

    // MARK: - Test

    func testExtractionAccuracy() async throws {
        let providerURL = resolveProviderURL()
        guard let providerURL else {
            throw XCTSkip("No LLM provider configured — set JOBHUNT_LLM_URL env var to run eval")
        }

        let provider = LMStudioProvider(baseURL: providerURL, model: resolveModel())

        print("\n=== LLM Extraction Eval ===")
        print("Provider URL: \(providerURL)")
        print("Model: \(resolveModel())\n")

        var totalChecks = 0
        var passedChecks = 0

        for fixture in Self.fixtures {
            print("--- \(fixture.name) ---")
            do {
                let result = try await runExtraction(fixture: fixture, provider: provider)
                let (passed, total) = scoreFixture(fixture: fixture, result: result)
                passedChecks += passed
                totalChecks += total
                let pct = total > 0 ? Int(Double(passed) / Double(total) * 100) : 0
                print("  Score: \(passed)/\(total) (\(pct)%)\n")
            } catch {
                print("  ERROR: \(error.localizedDescription)\n")
                totalChecks += 1 // count as a failed check
            }
        }

        let overallPct = totalChecks > 0 ? Int(Double(passedChecks) / Double(totalChecks) * 100) : 0
        print("=== Overall: \(passedChecks)/\(totalChecks) checks passed (\(overallPct)%) ===\n")
        // Intentionally not failing — this is a reporting harness, not a correctness gate.
    }

    // MARK: - Private helpers

    private func resolveProviderURL() -> String? {
        if let env = ProcessInfo.processInfo.environment["JOBHUNT_LLM_URL"], !env.isEmpty {
            return env
        }
        let configFile = URL.homeDirectory.appending(path: ".jobhunt-lmstudio-url")
        if let contents = try? String(contentsOf: configFile, encoding: .utf8) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private func resolveModel() -> String {
        ProcessInfo.processInfo.environment["JOBHUNT_LLM_MODEL"] ?? "gemma-4-e4b-it-mlx"
    }

    private func runExtraction(
        fixture: ExtractionFixture,
        provider: some LLMProvider
    ) async throws -> [String: Any] {
        let messages = PromptBuilder.buildExtractionPrompt(
            description: fixture.description,
            url: fixture.url,
            pageTitle: fixture.pageTitle
        )
        let request = ChatRequest(messages: messages, model: resolveModel())
        let response = try await provider.complete(request)
        print("  Model: \(response.model)  chars: \(response.content.count)")

        // Best-effort JSON parse — same repair path the app uses
        let repaired = (try? repairExtractedJSON(response.content)) ?? response.content
        guard let data = repaired.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("  WARN: could not parse response as JSON")
            return [:]
        }
        return parsed
    }

    /// Attempts to extract JSON from a raw LLM response (handles markdown code fences).
    private func repairExtractedJSON(_ raw: String) throws -> String {
        let stripped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip ```json ... ``` fences
        if stripped.hasPrefix("```") {
            let lines = stripped.components(separatedBy: "\n")
            let inner = lines.dropFirst().dropLast().joined(separator: "\n")
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Find first { ... }
        if let start = stripped.firstIndex(of: "{"),
           let end = stripped.lastIndex(of: "}") {
            return String(stripped[start ... end])
        }
        return stripped
    }

    private func scoreFixture(
        fixture: ExtractionFixture,
        result: [String: Any]
    ) -> (passed: Int, total: Int) {
        var passed = 0
        var total = 0
        func check(_ label: String, _ ok: Bool, got: String, expected: String) {
            total += 1
            print("  [\(ok ? "PASS" : "FAIL")] \(label): got=\(got)  expected=\(expected)")
            if ok { passed += 1 }
        }
        let fields = extractFields(from: result)
        scoreScalarFields(fixture: fixture, fields: fields, check: check)
        scoreListFields(fixture: fixture, fields: fields, check: check)
        return (passed, total)
    }

    // swiftlint:disable:next large_tuple
    private func extractFields(from result: [String: Any]) -> (
        company: String, title: String, remoteType: String,
        salaryMin: Int?, salaryMax: Int?, currency: String,
        skills: [String], requirements: [String]
    ) {
        (
            company: (result["company"] as? String) ?? "",
            title: (result["title"] as? String) ?? "",
            remoteType: (result["remote_type"] as? String) ?? "",
            salaryMin: result["salary_min"] as? Int,
            salaryMax: result["salary_max"] as? Int,
            currency: (result["salary_currency"] as? String) ?? "",
            skills: (result["skills"] as? [Any])?.compactMap { $0 as? String } ?? [],
            requirements: (result["requirements"] as? [Any])?.compactMap { $0 as? String } ?? []
        )
    }

    private func scoreScalarFields(
        fixture: ExtractionFixture,
        // swiftlint:disable:next large_tuple
        fields: (
            company: String,
            title: String,
            remoteType: String,
            salaryMin: Int?,
            salaryMax: Int?,
            currency: String,
            skills: [String],
            requirements: [String]
        ),
        check: (String, Bool, String, String) -> Void
    ) {
        if let exp = fixture.expectedCompany {
            check("company", fields.company.lowercased().contains(exp.lowercased()), got: fields.company, expected: exp)
        }
        if let exp = fixture.expectedTitleContains {
            check(
                "title",
                fields.title.lowercased().contains(exp.lowercased()),
                got: fields.title,
                expected: "contains '\(exp)'"
            )
        }
        if let exp = fixture.expectedRemoteType {
            check("remote_type", fields.remoteType == exp, got: fields.remoteType, expected: exp)
        }
        if let exp = fixture.expectedSalaryMin {
            check(
                "salary_min",
                fields.salaryMin == exp,
                got: fields.salaryMin.map(String.init) ?? "nil",
                expected: "\(exp)"
            )
        }
        if let exp = fixture.expectedSalaryMax {
            check(
                "salary_max",
                fields.salaryMax == exp,
                got: fields.salaryMax.map(String.init) ?? "nil",
                expected: "\(exp)"
            )
        }
        if let exp = fixture.expectedSalaryCurrency {
            check(
                "salary_currency",
                fields.currency.lowercased() == exp.lowercased(),
                got: fields.currency,
                expected: exp
            )
        }
    }

    private func scoreListFields(
        fixture: ExtractionFixture,
        // swiftlint:disable:next large_tuple
        fields: (
            company: String,
            title: String,
            remoteType: String,
            salaryMin: Int?,
            salaryMax: Int?,
            currency: String,
            skills: [String],
            requirements: [String]
        ),
        check: (String, Bool, String, String) -> Void
    ) {
        if !fixture.expectedSkillsAny.isEmpty {
            let text = fields.skills.joined(separator: " ").lowercased()
            let hit = fixture.expectedSkillsAny.contains { text.contains($0.lowercased()) }
            check(
                "skills (any-of)",
                hit,
                got: fields.skills.prefix(3).joined(separator: ", "),
                expected: "any of: \(fixture.expectedSkillsAny.prefix(3).joined(separator: ", "))"
            )
        }
        if !fixture.expectedRequirementsAny.isEmpty {
            let text = fields.requirements.joined(separator: " ").lowercased()
            let hit = fixture.expectedRequirementsAny.contains { text.contains($0.lowercased()) }
            check(
                "requirements (any-of)",
                hit,
                got: fields.requirements.prefix(2).joined(separator: "; "),
                expected: "any of: \(fixture.expectedRequirementsAny.prefix(3).joined(separator: ", "))"
            )
        }
    }
}

// swiftlint:enable type_body_length
