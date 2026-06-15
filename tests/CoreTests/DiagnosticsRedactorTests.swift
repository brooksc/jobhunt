import XCTest
@testable import JobhuntCore

final class DiagnosticsRedactorTests: XCTestCase {
    func testRedactsFilePaths() {
        let input = "Couldn't open /Users/alice/Library/Application Support/Jobhunt/jobhunt.store"
        let out = DiagnosticsRedactor.redact(input)
        XCTAssertFalse(out.contains("/Users/alice"), "Home path must be redacted")
        XCTAssertTrue(out.contains("[redacted]"))
    }

    func testRedactsVarAndPrivateAndTmpPaths() {
        for path in ["/var/folders/xy/abc/probe.store", "/private/tmp/leak.txt", "/tmp/scratch.db"] {
            let out = DiagnosticsRedactor.redact("error at \(path)")
            XCTAssertFalse(out.contains(path), "\(path) must be redacted")
        }
    }

    func testRedactsURLQueryStrings() {
        let input = "request to https://api.example.com/v1/jobs?token=secret123&user=alice failed"
        let out = DiagnosticsRedactor.redact(input)
        XCTAssertFalse(out.contains("token=secret123"), "Query string must be redacted")
        XCTAssertFalse(out.contains("user=alice"))
        XCTAssertTrue(out.contains("https://api.example.com/v1/jobs"), "Path is kept, query stripped")
    }

    func testRedactsBearerTokens() {
        let out = DiagnosticsRedactor.redact("Authorization: Bearer abcDEF123456789ghijkl")
        XCTAssertFalse(out.contains("abcDEF123456789ghijkl"), "Bearer token must be redacted")
    }

    func testRedactsOpenAIAndGoogleKeys() {
        let out1 = DiagnosticsRedactor.redact("key sk-proj-ABCDEFGH1234567890 invalid")
        XCTAssertFalse(out1.contains("sk-proj-ABCDEFGH1234567890"), "OpenAI-style key must be redacted")
        let out2 = DiagnosticsRedactor.redact("AIzaSyA1234567890abcdefghijklmnop rejected")
        XCTAssertFalse(out2.contains("AIzaSyA1234567890abcdefghijklmnop"), "Google API key must be redacted")
    }

    func testLeavesBenignTextIntact() {
        let input = "Request timed out after 30s (HTTP 503)"
        XCTAssertEqual(DiagnosticsRedactor.redact(input), input)
    }
}
