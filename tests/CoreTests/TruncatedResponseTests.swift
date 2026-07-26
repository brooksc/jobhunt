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
    func testTruncatedResponseGetsAnActionableMessage() {
        let cutOff = ExtractionEngineError.invalidJSON(#"{"company":"Instacart","skills":["a","#)
        XCTAssertEqual(
            cutOff.errorDescription,
            "LLM response was incomplete — it ended mid-JSON, so the model was likely cut off"
        )
        // Genuinely malformed (but complete) output keeps the original wording.
        let garbage = ExtractionEngineError.invalidJSON("I could not find a job posting here.")
        XCTAssertEqual(garbage.errorDescription, "LLM response could not be parsed as JSON")
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
