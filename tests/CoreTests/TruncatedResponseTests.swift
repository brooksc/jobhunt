import Foundation
import XCTest
@testable import JobhuntCore

/// Diagnosing LLM responses that stop mid-answer. Three extraction jobs failed identically on every
/// retry with a bare "could not be parsed as JSON": the model returned well-formed JSON that simply
/// ended partway through, and nothing in the pipeline could say so.
final class TruncatedResponseTests: XCTestCase {
    // MARK: - Unbalanced detection

    func testCompleteJSONIsBalanced() {
        XCTAssertFalse(ExtractionEngineError.isUnbalanced(#"{"company":"Acme","skills":["a","b"]}"#))
        XCTAssertFalse(ExtractionEngineError.isUnbalanced("{}"))
    }

    /// The shape actually observed: valid prefix, cut off inside a nested array.
    func testResponseCutOffMidArrayIsUnbalanced() {
        let truncated = #"{"company":"Instacart","nice_to_haves":["Large language models (LLMs)","#
        XCTAssertTrue(ExtractionEngineError.isUnbalanced(truncated))
    }

    func testResponseCutOffMidStringIsUnbalanced() {
        XCTAssertTrue(ExtractionEngineError.isUnbalanced(#"{"company":"Insta"#))
    }

    /// Braces and brackets inside string values must not be counted as structure.
    func testPunctuationInsideStringsDoesNotSkewBalance() {
        XCTAssertFalse(ExtractionEngineError.isUnbalanced(#"{"note":"salary {see [range]} below"}"#))
        XCTAssertFalse(ExtractionEngineError.isUnbalanced(#"{"note":"escaped \" quote { here"}"#))
    }

    /// A truncated response must say so, rather than the generic parse message that sent this
    /// investigation looking at the wrong layer.
    func testTruncatedResponseGetsAnActionableMessage() throws {
        let cutOff = ExtractionEngineError.invalidJSON(#"{"company":"Instacart","skills":["a","#)
        XCTAssertEqual(
            cutOff.errorDescription,
            "LLM response was incomplete — it ended mid-JSON, so the model was likely cut off"
        )
        // Genuinely malformed (but complete) output keeps the original wording, now followed by the
        // parser's own account of where it gave up — the detail job #861 needed and didn't have.
        let garbage = ExtractionEngineError.invalidJSON("I could not find a job posting here.")
        let message = try XCTUnwrap(garbage.errorDescription)
        XCTAssertTrue(
            message.hasPrefix("LLM response could not be parsed as JSON"),
            "the headline must stay recognisable: \(message)"
        )
        XCTAssertTrue(
            message.contains("line") || message.contains("character"),
            "the parser's position is the point of the detail: \(message)"
        )
    }

    /// Three identical failures on job #861 said only "could not be parsed as JSON" against a
    /// response that was complete at both ends — the fault was in the middle, and nothing recorded
    /// said where. The parser always knew.
    func testParserComplaintNamesWhatIsWrong() {
        // An unescaped control character inside a string — valid-looking at both ends.
        let raw = "{\"a\": \"one\u{01}two\"}"
        let complaint = ExtractionEngineError.parserComplaint(raw)
        XCTAssertFalse(complaint.isEmpty)
        XCTAssertTrue(
            complaint.lowercased().contains("character") || complaint.lowercased().contains("line"),
            "expected a positional complaint, got: \(complaint)"
        )
    }

    /// The complaint is the parser's, never the model's text.
    func testParserComplaintDoesNotEchoTheResponse() {
        let complaint = ExtractionEngineError.parserComplaint(#"{"company": "VerySpecificCompanyName"#)
        XCTAssertFalse(complaint.contains("VerySpecificCompanyName"), complaint)
    }

    /// The raw model text must never leak into a persisted error string.
    func testRawResponseIsNeverEchoedInTheMessage() throws {
        let secretish = ExtractionEngineError.invalidJSON(#"{"company":"VerySpecificCompanyName""#)
        let message = try XCTUnwrap(secretish.errorDescription)
        XCTAssertFalse(message.contains("VerySpecificCompanyName"), message)
    }

    // MARK: - Provider-level truncation

    func testTruncatedProviderErrorNamesReasoningSpend() {
        let error = LLMProviderError.truncated(completionTokens: 620, thinkingTokens: 15700)
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.contains("cut off at the output limit"), message)
        XCTAssertTrue(message.contains("15700"), "the reasoning spend is the actionable detail: \(message)")
    }

    func testTruncatedWithoutUsageStillExplainsItself() {
        let error = LLMProviderError.truncated(completionTokens: nil, thinkingTokens: nil)
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.contains("cut off at the output limit"), message)
        XCTAssertTrue(message.contains("Raise the output limit"), message)
    }
}
