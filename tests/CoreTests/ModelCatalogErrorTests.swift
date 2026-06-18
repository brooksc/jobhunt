import XCTest
@testable import JobhuntCore

/// The model-fetch error must be actionable — a bare status code (e.g. the Google 403 a restricted
/// key returns) left users stuck. It now explains 401/403 and surfaces the provider's own message.
final class ModelCatalogErrorTests: XCTestCase {

    func test403_explainsRestrictedKey() {
        let message = ModelCatalogError.httpError(statusCode: 403, serverMessage: nil).errorDescription ?? ""
        XCTAssertTrue(message.contains("403"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("rejected"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("restriction"))
    }

    func test403_includesProviderMessage() {
        let message = ModelCatalogError.httpError(
            statusCode: 403,
            serverMessage: "Generative Language API has not been used in project 123 before or it is disabled."
        ).errorDescription ?? ""
        XCTAssertTrue(message.contains("has not been used in project 123"))
    }

    /// A 4xx that isn't an auth failure shouldn't get the key-rejection hint, just the code + message.
    func testOtherHTTPError_noAuthHint() {
        let message = ModelCatalogError.httpError(statusCode: 500, serverMessage: "boom").errorDescription ?? ""
        XCTAssertTrue(message.contains("500"))
        XCTAssertTrue(message.contains("boom"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("rejected"))
    }

    // MARK: - Diagnostic key fingerprint (TASK-489) — never leaks the full secret

    func testKeyFingerprint_safeShape() {
        let fp = ModelCatalog.keyFingerprint("AQ.AReplacedFakeTestKeyNeverRealRedactedgXZg")
        XCTAssertTrue(fp.contains("AQ.A"))      // first 4
        XCTAssertTrue(fp.contains("gXZg"))      // last 4
        XCTAssertTrue(fp.contains("ws=false"))
        XCTAssertTrue(fp.contains("ascii=true"))
        XCTAssertFalse(fp.contains("Ab8RN6"))   // middle of the key is NOT logged
    }

    func testKeyFingerprint_flagsWhitespaceAndEmpty() {
        XCTAssertEqual(ModelCatalog.keyFingerprint(""), "EMPTY")
        XCTAssertTrue(ModelCatalog.keyFingerprint("AIzaSExample ").contains("ws=true"))
    }

    // MARK: - Text-model filter (drop image/tts/etc. from the model picker)

    func testTextGenerationModels_keepsChatModels_dropsNonText() {
        let input = [
            "gemini-2.5-flash", "gemini-2.5-pro", "gemini-3-pro-preview", "gemini-flash-latest",
            "gemma-4-31b-it",
            // non-text that should be filtered out:
            "gemini-2.5-flash-image", "gemini-3-pro-image", "gemini-2.5-flash-preview-tts",
            "lyria-3-pro-preview", "lyria-3-clip-preview", "nano-banana-pro-preview",
            "gemini-robotics-er-1.5-preview", "gemini-2.5-computer-use-preview-10-2025",
            "deep-research-pro-preview-12-2025", "antigravity-preview-05-2026",
            "text-embedding-004", "veo-3", "whisper-1", "dall-e-3", "tts-1"
        ]
        let kept = ModelCatalog.textGenerationModels(input)
        XCTAssertEqual(Set(kept), ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-3-pro-preview",
                                   "gemini-flash-latest", "gemma-4-31b-it"])
    }
}
