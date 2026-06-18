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
}
