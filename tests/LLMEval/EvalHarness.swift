import XCTest
@testable import JobhuntCore

// MARK: - LLMEvalHarness

// swiftlint:disable type_body_length
/// Eval harness for LLM extraction accuracy.
///
/// Reporting mode (default): prints field-by-field accuracy but never fails.
///   JOBHUNT_LLM_URL=http://127.0.0.1:1234 xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
///
/// Threshold mode: fails when overall accuracy falls below the configured minimum.
///   JOBHUNT_LLM_URL=http://127.0.0.1:1234 JOBHUNT_LLM_MIN_ACCURACY=80 \
///     xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
///
/// The test skips gracefully when no provider is configured.
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
        let expectedRemoteType: RemoteType?
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
            expectedRemoteType: .remote,
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
            expectedRemoteType: .hybrid,
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
            expectedRemoteType: .remote,
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

        let model = resolveModel()
        let provider = LMStudioProvider(baseURL: providerURL, model: model)
        let minAccuracy = resolveMinAccuracy()

        print("\n=== LLM Extraction Eval ===")
        print("Provider URL: \(providerURL)")
        print("Model: \(model)")
        if let min = minAccuracy {
            print("Threshold mode: fail below \(min)%")
        } else {
            print("Reporting mode: no accuracy threshold")
        }
        print("")

        var totalChecks = 0
        var passedChecks = 0

        let settings = makeExtractionSettings(model: model, providerURL: providerURL)

        for fixture in Self.fixtures {
            print("--- \(fixture.name) ---")
            do {
                let result = try await runExtraction(fixture: fixture, provider: provider, settings: settings)
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

        if let min = minAccuracy {
            XCTAssertGreaterThanOrEqual(
                overallPct, min,
                "Accuracy \(overallPct)% is below threshold \(min)%. Set JOBHUNT_LLM_MIN_ACCURACY to adjust."
            )
        }
        // Without a threshold, the test always passes (reporting mode).
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

    /// Returns the minimum accuracy percentage from JOBHUNT_LLM_MIN_ACCURACY, or nil for reporting mode.
    private func resolveMinAccuracy() -> Int? {
        guard let raw = ProcessInfo.processInfo.environment["JOBHUNT_LLM_MIN_ACCURACY"],
              let value = Int(raw), value > 0 else { return nil }
        return value
    }

    private func makeExtractionSettings(model: String, providerURL: String) -> ExtractionSettings {
        ExtractionSettings(
            llmModel: model,
            llmProvider: "lmstudio",
            llmBaseURL: providerURL,
            consentGranted: true,
            preferredLocations: "",
            locationFilterEnabled: false,
            locationAllowRemote: true,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        )
    }

    private func runExtraction(
        fixture: ExtractionFixture,
        provider: some LLMProvider,
        settings: ExtractionSettings
    ) async throws -> ExtractionResult {
        let snapshot = JobExtractionSnapshot(
            captureURL: fixture.url,
            captureCanonicalURL: nil,
            capturePageTitle: fixture.pageTitle,
            captureCleanedDescription: fixture.description,
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        let result = try await ExtractionEngine.extract(snapshot: snapshot, provider: provider, settings: settings)
        print("  Model: \(result.extractionModel)  chars: \(result.responseChars)")
        return result
    }

    private func scoreFixture(
        fixture: ExtractionFixture,
        result: ExtractionResult
    ) -> (passed: Int, total: Int) {
        var passed = 0
        var total = 0
        func check(_ label: String, _ ok: Bool, got: String, expected: String) {
            total += 1
            print("  [\(ok ? "PASS" : "FAIL")] \(label): got=\(got)  expected=\(expected)")
            if ok { passed += 1 }
        }

        if let exp = fixture.expectedCompany {
            check("company", (result.company ?? "").lowercased().contains(exp.lowercased()),
                  got: result.company ?? "", expected: exp)
        }
        if let exp = fixture.expectedTitleContains {
            check("title", (result.title ?? "").lowercased().contains(exp.lowercased()),
                  got: result.title ?? "", expected: "contains '\(exp)'")
        }
        if let exp = fixture.expectedRemoteType {
            check("remote_type", result.remoteType == exp,
                  got: result.remoteType?.rawValue ?? "nil", expected: exp.rawValue)
        }
        if let exp = fixture.expectedSalaryMin {
            check("salary_min", result.salaryMin == exp,
                  got: result.salaryMin.map(String.init) ?? "nil", expected: "\(exp)")
        }
        if let exp = fixture.expectedSalaryMax {
            check("salary_max", result.salaryMax == exp,
                  got: result.salaryMax.map(String.init) ?? "nil", expected: "\(exp)")
        }
        if let exp = fixture.expectedSalaryCurrency {
            check("salary_currency", (result.salaryCurrency ?? "").lowercased() == exp.lowercased(),
                  got: result.salaryCurrency ?? "", expected: exp)
        }

        // Skills and requirements come from extractedJSON since ExtractionResult doesn't expose them directly
        if !fixture.expectedSkillsAny.isEmpty || !fixture.expectedRequirementsAny.isEmpty {
            let rawDict = parseExtractedJSON(result.extractedJSON)
            let skills = (rawDict["skills"] as? [Any])?.compactMap { $0 as? String } ?? []
            let reqs = (rawDict["requirements"] as? [Any])?.compactMap { $0 as? String } ?? []

            if !fixture.expectedSkillsAny.isEmpty {
                let text = skills.joined(separator: " ").lowercased()
                let hit = fixture.expectedSkillsAny.contains { text.contains($0.lowercased()) }
                check("skills (any-of)", hit,
                      got: skills.prefix(3).joined(separator: ", "),
                      expected: "any of: \(fixture.expectedSkillsAny.prefix(3).joined(separator: ", "))")
            }
            if !fixture.expectedRequirementsAny.isEmpty {
                let text = reqs.joined(separator: " ").lowercased()
                let hit = fixture.expectedRequirementsAny.contains { text.contains($0.lowercased()) }
                check("requirements (any-of)", hit,
                      got: reqs.prefix(2).joined(separator: "; "),
                      expected: "any of: \(fixture.expectedRequirementsAny.prefix(3).joined(separator: ", "))")
            }
        }

        return (passed, total)
    }

    private func parseExtractedJSON(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }
}

// swiftlint:enable type_body_length
