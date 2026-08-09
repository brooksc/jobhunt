import Foundation
import XCTest
@testable import JobhuntCore

/// Previewing what an application will ask for (TASK-635).
///
/// The fixture is trimmed from a real `?questions=true` response (gitlab/8503792002, checked
/// 2026-08-09) — same nesting, same field types, same mix of boilerplate and real questions.
final class ApplicationFormPreviewTests: XCTestCase {
    private let payload = Data("""
    {
      "id": 8503792002,
      "questions": [
        { "label": "First Name", "required": true,
          "fields": [{ "name": "first_name", "type": "input_text" }] },
        { "label": "Email", "required": true,
          "fields": [{ "name": "email", "type": "input_text" }] },
        { "label": "Resume/CV", "required": true,
          "fields": [{ "name": "resume", "type": "input_file" },
                     { "name": "resume_text", "type": "textarea" }] },
        { "label": "Cover Letter", "required": false,
          "fields": [{ "name": "cover_letter", "type": "input_file" },
                     { "name": "cover_letter_text", "type": "textarea" }] },
        { "label": "LinkedIn Profile", "required": false,
          "fields": [{ "name": "question_1", "type": "input_text" }] },
        { "label": "It is important to us to create an accessible and inclusive interview experience. Please let us know if there are any adjustments we can make to assist you.", "required": false,
          "fields": [{ "name": "question_2", "type": "input_text" }] },
        { "label": "Will you now or in the future require sponsorship for a visa?", "required": true,
          "fields": [{ "name": "question_3", "type": "multi_value_single_select" }] }
      ]
    }
    """.utf8)

    private func preview() throws -> ApplicationFormPreview {
        try XCTUnwrap(ApplicationFormPreview.decode(payload))
    }

    func testDecodesQuestionsWithRequirednessAndTypes() throws {
        let preview = try preview()
        XCTAssertEqual(preview.questions.count, 7)
        XCTAssertEqual(preview.requiredCount, 4)
        XCTAssertEqual(preview.optionalCount, 3)
        XCTAssertTrue(preview.asksForResume)
        XCTAssertTrue(preview.asksForCoverLetter)
    }

    /// #4: a board that doesn't publish its form is not a form with no questions, and showing "asks
    /// for nothing" would be worse than showing nothing.
    func testAbsentQuestionsDecodeToNil() {
        XCTAssertNil(ApplicationFormPreview.decode(Data(#"{"id":1,"title":"X"}"#.utf8)))
        XCTAssertNil(ApplicationFormPreview.decode(Data(#"{"questions":[]}"#.utf8)))
        XCTAssertNil(ApplicationFormPreview.decode(Data("garbage".utf8)))
    }

    /// The whole point of the preview is telling a two-minute application from a forty-minute one,
    /// so the name/email/résumé fields every posting shares must not count toward that.
    func testBoilerplateAndUploadsAreNotSubstantive() throws {
        let labels = try preview().substantiveQuestions.map(\.label)
        XCTAssertFalse(labels.contains("First Name"))
        XCTAssertFalse(labels.contains("Email"))
        XCTAssertFalse(labels.contains("LinkedIn Profile"))
        XCTAssertFalse(labels.contains("Resume/CV"))
        XCTAssertFalse(labels.contains("Cover Letter"))
        XCTAssertEqual(labels.count, 2)
    }

    /// #2: a long free-text prompt is an essay; a dropdown isn't, however long its label.
    func testEffortIsJudgedOnTypeAndLength() throws {
        let substantive = try preview().substantiveQuestions
        let essay = try XCTUnwrap(substantive.first { $0.label.hasPrefix("It is important") })
        let dropdown = try XCTUnwrap(substantive.first { $0.label.hasPrefix("Will you now") })
        XCTAssertTrue(essay.isEffortful)
        XCTAssertFalse(dropdown.isEffortful)
        XCTAssertEqual(try preview().essayCount, 1)
    }

    func testSummaryNamesWhatItCosts() throws {
        let summary = try XCTUnwrap(preview().summary)
        XCTAssertTrue(summary.contains("cover letter"), summary)
        XCTAssertTrue(summary.contains("1 written question"), summary)
        XCTAssertTrue(summary.contains("1 extra question"), summary)
    }

    /// A form that asks only for a name and a résumé needs no warning — a badge on every job is one
    /// nobody reads.
    func testAPlainFormHasNoSummary() throws {
        let plain = try XCTUnwrap(ApplicationFormPreview.decode(Data("""
        { "questions": [
          { "label": "First Name", "required": true,
            "fields": [{ "name": "first_name", "type": "input_text" }] },
          { "label": "Resume/CV", "required": true,
            "fields": [{ "name": "resume", "type": "input_file" }] }
        ] }
        """.utf8)))
        XCTAssertNil(plain.summary)
    }

    /// #3: the agent prompt needs the fields in form order with their requiredness — both matter to
    /// whatever is drafting the answers.
    func testPromptContextListsEveryFieldWithRequiredness() throws {
        let context = try preview().promptContext
        XCTAssertEqual(context.split(separator: "\n").count, 7)
        XCTAssertTrue(context.contains("- Email [required]"), context)
        XCTAssertTrue(context.contains("- Cover Letter [optional]"), context)
        // Order follows the form, so the agent fills it top to bottom.
        let first = try XCTUnwrap(context.split(separator: "\n").first)
        XCTAssertTrue(first.contains("First Name"), String(first))
    }

    func testQuestionsWithoutLabelsAreSkipped() throws {
        let preview = try XCTUnwrap(ApplicationFormPreview.decode(Data("""
        { "questions": [
          { "required": true, "fields": [{ "name": "x", "type": "input_text" }] },
          { "label": "  ", "required": true, "fields": [] },
          { "label": "Real question", "required": true, "fields": [] }
        ] }
        """.utf8)))
        XCTAssertEqual(preview.questions.map(\.label), ["Real question"])
    }
}
