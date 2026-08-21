import Foundation
import XCTest
@testable import JobhuntCore

/// Job #861 failed extraction three times with "LLM response could not be parsed as JSON" and left
/// three previews of perfectly valid JSON — because the preview was the first 2,000 characters and
/// the response was longer than that. The evidence was always in the part being discarded.
final class LLMResponsePreviewTests: XCTestCase {
    func testShortResponsesAreKeptWhole() {
        let raw = "{\"company\": \"Acme\"}"
        XCTAssertEqual(LLMResponsePreview.forUnparseableJSON(raw), raw)
    }

    /// The point of the change: whatever is at the END of the response has to survive.
    func testTheEndOfALongResponseIsKept() {
        let filler = String(repeating: "x", count: 5000)
        let raw = "{\"a\": \"" + filler + "\", \"skills\": [\"one\", \"two\""
        let preview = LLMResponsePreview.forUnparseableJSON(raw)

        XCTAssertTrue(
            preview.hasSuffix("\"skills\": [\"one\", \"two\""),
            "the unterminated tail is the whole diagnosis — it must be in the preview"
        )
        XCTAssertTrue(preview.hasPrefix("{\"a\": \"xxx"), "the head identifies the response")
    }

    /// Nobody should read the two halves as contiguous text.
    func testTheElisionSaysHowMuchIsMissing() {
        let raw = String(repeating: "y", count: LLMResponsePreview.budget + 500)
        let preview = LLMResponsePreview.forUnparseableJSON(raw)
        XCTAssertTrue(preview.contains("characters omitted"), "preview must not look contiguous")
        XCTAssertTrue(preview.contains("500 characters omitted"))
    }

    /// It stays bounded — this goes in the store on every failed attempt.
    func testPreviewStaysWithinBudget() {
        for length in [2001, 5000, 50000] {
            let preview = LLMResponsePreview.forUnparseableJSON(String(repeating: "z", count: length))
            XCTAssertLessThanOrEqual(
                preview.count, LLMResponsePreview.budget + LLMResponsePreview.elisionMarker.count + 8,
                "preview for a \(length)-character response is unbounded"
            )
        }
    }

    /// Exactly at the budget there is nothing to elide.
    func testExactlyAtBudgetIsUnchanged() {
        let raw = String(repeating: "q", count: LLMResponsePreview.budget)
        XCTAssertEqual(LLMResponsePreview.forUnparseableJSON(raw), raw)
    }
}
