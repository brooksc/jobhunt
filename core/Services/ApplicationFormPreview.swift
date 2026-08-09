import Foundation

/// What a job's application form will actually ask for (TASK-635).
///
/// Effort is invisible from a job posting: two roles that read identically can be a two-minute
/// upload and a forty-minute set of essays. Greenhouse publishes the form, so the difference can be
/// shown before the user commits to starting.
///
/// Read-only. Nothing here submits anything.
public struct ApplicationFormPreview: Sendable, Equatable {
    public struct Question: Sendable, Equatable, Identifiable {
        public let label: String
        public let required: Bool
        /// Greenhouse field types for this question — a question can have several (a résumé is a
        /// file *or* pasted text).
        public let fieldTypes: [String]
        public var id: String {
            label
        }

        /// Whether answering this takes real writing rather than a click or a paste.
        ///
        /// Judged on the field type plus the label's length: a `textarea` is the clearest signal,
        /// and a long question label is nearly always an essay prompt (the shortest essay question
        /// on the board checked was 96 characters; the longest non-essay label was 20).
        public var isEffortful: Bool {
            if fieldTypes.contains("textarea") { return true }
            return label.count > 80 && fieldTypes.contains("input_text")
        }
    }

    public let questions: [Question]

    /// Standard identity fields every application asks for. Counting them as "effort" would make
    /// every posting look the same, which defeats the purpose of the preview.
    static let boilerplateLabels: Set<String> = [
        "first name", "last name", "email", "phone", "location", "location (city)",
        "linkedin profile", "website", "full name"
    ]

    public var requiredCount: Int {
        questions.count(where: \.required)
    }

    public var optionalCount: Int {
        questions.count(where: { !$0.required })
    }

    public var asksForResume: Bool {
        mentions("resume") || mentions("cv")
    }

    public var asksForCoverLetter: Bool {
        mentions("cover letter")
    }

    /// Questions that are neither boilerplate nor the résumé/cover-letter uploads — the ones that
    /// actually make one application longer than another.
    public var substantiveQuestions: [Question] {
        questions.filter { question in
            let label = question.label.lowercased()
            if Self.boilerplateLabels.contains(label) { return false }
            if label.contains("resume") || label.contains("cv") { return false }
            if label.contains("cover letter") { return false }
            return true
        }
    }

    public var essayCount: Int {
        substantiveQuestions.count(where: \.isEffortful)
    }

    /// One line for the job detail: what this will cost you to fill in.
    ///
    /// Returns nil when there's nothing distinguishing to say — a form that asks only for a name and
    /// a résumé doesn't need a warning, and a badge on every job is one nobody reads.
    public var summary: String? {
        var parts: [String] = []
        if asksForCoverLetter { parts.append("cover letter") }
        if essayCount > 0 {
            parts.append("\(essayCount) written question\(essayCount == 1 ? "" : "s")")
        }
        let others = substantiveQuestions.count - essayCount
        if others > 0 { parts.append("\(others) extra question\(others == 1 ? "" : "s")") }
        guard !parts.isEmpty else { return nil }
        return "Application asks for: " + parts.joined(separator: ", ")
    }

    /// The form as plain text, for the Auto-Apply prompt (#3). Ordered as the form is, and marked
    /// required/optional, because both matter to whatever is drafting the answers.
    public var promptContext: String {
        questions.map { question in
            "- \(question.label) [\(question.required ? "required" : "optional")]"
        }
        .joined(separator: "\n")
    }

    private func mentions(_ needle: String) -> Bool {
        questions.contains { $0.label.lowercased().contains(needle) }
    }

    /// Decodes `?questions=true`. Returns nil when the payload carries no questions at all — a board
    /// that doesn't publish them is a different thing from a form with none, and showing "asks for
    /// nothing" would be wrong (#4).
    public static func decode(_ data: Data) -> ApplicationFormPreview? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawQuestions = raw["questions"] as? [[String: Any]], !rawQuestions.isEmpty
        else { return nil }

        let questions = rawQuestions.compactMap { entry -> Question? in
            guard let label = (entry["label"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty
            else { return nil }
            let types = (entry["fields"] as? [[String: Any]])?
                .compactMap { $0["type"] as? String } ?? []
            return Question(
                label: label,
                required: entry["required"] as? Bool ?? false,
                fieldTypes: types
            )
        }
        return questions.isEmpty ? nil : ApplicationFormPreview(questions: questions)
    }
}
