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

    // TASK-550: named secret fields/headers in colon and equals forms (case-insensitive). The field
    // name is preserved; only the value is redacted.
    func testRedactsNamedSecretFieldsColonForm() {
        let cases = [
            "x-api-key: abc123SECRET",
            "X-Api-Key: abc123SECRET",
            "api_key: abc123SECRET",
            "Authorization: abc123SECRET",
            "access_token: abc123SECRET",
            "refresh_token: abc123SECRET",
            "client_secret: abc123SECRET"
        ]
        for input in cases {
            let out = DiagnosticsRedactor.redact(input)
            XCTAssertFalse(out.contains("abc123SECRET"), "value must be redacted in: \(input)")
            XCTAssertTrue(out.contains("[redacted]"), "marker expected in: \(input)")
        }
    }

    func testRedactsNamedSecretFieldsEqualsForm() {
        let out = DiagnosticsRedactor.redact("client_secret=topSECRETvalue&grant_type=client_credentials")
        XCTAssertFalse(out.contains("topSECRETvalue"), "secret value must be redacted")
        // Trailing benign pair is preserved (value stops at '&').
        XCTAssertTrue(out.contains("grant_type=client_credentials"))
    }

    func testRedactsBasicAuthCredential() {
        let out = DiagnosticsRedactor.redact("Authorization: Basic dXNlcjpwYXNzd29yZA==")
        XCTAssertFalse(out.contains("dXNlcjpwYXNzd29yZA=="), "Basic credential must be redacted")
    }

    // TASK-550 AC#3: benign HTTP/status text is not mangled by the new field patterns.
    func testLeavesBenignHTTPStatusTextIntact() {
        for input in [
            "HTTP 401 Unauthorized",
            "Could not connect to server (NSURLErrorDomain Code=-1004)",
            "Status: 200 OK"
        ] {
            XCTAssertEqual(DiagnosticsRedactor.redact(input), input, "benign text changed: \(input)")
        }
    }
}
