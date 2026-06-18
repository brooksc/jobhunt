import Foundation

/// Pure response logic for a mock OpenAI-compatible endpoint. Used by `MockLLMServer` (and directly
/// in unit tests) to exercise the extraction / fit-scoring inference path without a real provider or
/// API key. Responses are deterministic and lightly input-aware — the extraction echoes the page
/// title it sees in the prompt — so a test/UI run proves the real job's data round-tripped, not a
/// static blob.
///
/// Test-support only: compiled into the test targets (CoreTests, AppUITests), never shipped in the app.
enum MockLLMResponder {

    enum Kind { case extraction, fit }

    /// The full `/v1/chat/completions` JSON response string for a request body. The request is
    /// classified by `response_format.json_schema.name` ("job_extraction" / "fit_score"), falling
    /// back to prompt keywords, and the matching structured JSON is returned as the assistant message.
    static func chatCompletion(requestBody: Data) -> String {
        let body = (try? JSONSerialization.jsonObject(with: requestBody)) as? [String: Any]
        let model = (body?["model"] as? String) ?? "mock-model"
        let content: String
        switch classify(body: body) {
        case .fit:        content = fitContentJSON()
        case .extraction: content = extractionContentJSON(pageTitle: pageTitle(in: body))
        }
        return jsonString([
            "id": "mock-cmpl-1",
            "object": "chat.completion",
            "model": model,
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": content],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150]
        ])
    }

    /// A minimal `/v1/models` response advertising the mock model (for "Fetch Models" / Test Connection).
    static func models() -> String {
        jsonString([
            "object": "list",
            "data": [["id": "mock-model", "object": "model", "owned_by": "mock"]]
        ])
    }

    // MARK: - Classification

    static func classify(body: [String: Any]?) -> Kind {
        if let rf = body?["response_format"] as? [String: Any],
           let js = rf["json_schema"] as? [String: Any],
           let name = js["name"] as? String {
            if name == "fit_score" { return .fit }
            if name == "job_extraction" { return .extraction }
        }
        // Fallback when the format was downgraded (json_object/text): the fit prompt is the only one
        // that talks about a résumé.
        return messagesText(body).localizedCaseInsensitiveContains("resume") ? .fit : .extraction
    }

    // MARK: - Input-aware extraction

    /// Recover the captured page title from the user prompt (`PromptBuilder` writes `Page title: …`).
    static func pageTitle(in body: [String: Any]?) -> String? {
        let text = messagesText(body)
        guard let range = text.range(of: "Page title: ") else { return nil }
        let line = text[range.upperBound...].prefix { $0 != "\n" }
        let title = line.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    /// Split a page title like "Senior iOS Engineer - Acme" / "… @ Acme" into (title, company).
    static func titleAndCompany(from pageTitle: String?) -> (title: String, company: String) {
        guard let pageTitle, !pageTitle.isEmpty else { return ("Mock Engineer", "MockCorp") }
        for separator in [" - ", " — ", " | ", " @ ", " at "] {
            if let r = pageTitle.range(of: separator) {
                let title = pageTitle[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let company = pageTitle[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !title.isEmpty, !company.isEmpty { return (title, company) }
            }
        }
        return (pageTitle, "MockCorp")
    }

    // MARK: - Canned structured payloads (snake_case keys the engine parses back)

    static func extractionContentJSON(pageTitle: String?) -> String {
        let (title, company) = titleAndCompany(from: pageTitle)
        return jsonString([
            "company": company,
            "title": title,
            "location": "Remote",
            "remote_type": "remote",
            "salary_min": 150_000,
            "salary_max": 200_000,
            "salary_hourly_min": NSNull(),
            "salary_hourly_max": NSNull(),
            "salary_currency": "USD",
            "salary_note": NSNull(),
            "employment_type": "full-time",
            "seniority": "senior",
            "skills": ["Swift", "SwiftUI", "Concurrency"],
            "summary": "Mock extraction for \(title) at \(company).",
            "requirements": ["5+ years iOS", "Swift"],
            "nice_to_haves": ["SwiftData"],
            "benefits": ["Health", "401(k)"],
            "application_url": NSNull(),
            "application_instructions": NSNull()
        ])
    }

    /// Dimensions match `FitScorer.dimensionWeights` exactly (names + weights) so validation passes;
    /// the scores weight-average to ~72.
    static func fitContentJSON() -> String {
        jsonString([
            "overall": 72,
            "summary": "Mock fit assessment.",
            "requirements_met": ["Swift", "iOS"],
            "requirements_not_met": ["Kotlin"],
            "dimensions": [
                ["name": "required_qualifications", "score": 75, "weight": 0.45, "rationale": "mock"],
                ["name": "preferred_qualifications", "score": 60, "weight": 0.05, "rationale": "mock"],
                ["name": "skills", "score": 80, "weight": 0.15, "rationale": "mock"],
                ["name": "experience_level", "score": 70, "weight": 0.20, "rationale": "mock"],
                ["name": "domain_fit", "score": 65, "weight": 0.15, "rationale": "mock"]
            ]
        ])
    }

    // MARK: - Helpers

    private static func messagesText(_ body: [String: Any]?) -> String {
        guard let messages = body?["messages"] as? [[String: Any]] else { return "" }
        return messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
