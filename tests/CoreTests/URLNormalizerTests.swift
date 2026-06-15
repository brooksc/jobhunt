import XCTest
@testable import JobhuntCore

/// TASK-443: shared captured-job URL validation policy.
final class URLNormalizerTests: XCTestCase {
    // MARK: - Valid HTTP/HTTPS

    func testValidHTTPSPassesThrough() throws {
        XCTAssertEqual(
            try URLNormalizer.validatedForIngestion("https://example.com/jobs/123"),
            "https://example.com/jobs/123"
        )
    }

    func testValidHTTPAccepted() throws {
        XCTAssertEqual(
            try URLNormalizer.validatedForIngestion("http://example.com/x"),
            "http://example.com/x"
        )
    }

    func testQueryAndFragmentPreserved() throws {
        // Validation must not strip query/fragment — the stored URL has to open the exact page.
        let url = "https://example.com/p?id=7&q=swift#section"
        XCTAssertEqual(try URLNormalizer.validatedForIngestion(url), url)
    }

    // MARK: - Whitespace + case normalization

    func testWhitespaceTrimmed() throws {
        XCTAssertEqual(
            try URLNormalizer.validatedForIngestion("   https://example.com/x  \n"),
            "https://example.com/x"
        )
    }

    func testSchemeAndHostLowercased_pathPreserved() throws {
        XCTAssertEqual(
            try URLNormalizer.validatedForIngestion("HTTPS://Example.COM/Jobs/AbC"),
            "https://example.com/Jobs/AbC"
        )
    }

    // MARK: - Unsupported schemes

    func testUnsupportedSchemesRejected() {
        for url in ["ftp://example.com/x", "file:///etc/passwd", "javascript:alert(1)", "mailto:a@b.com"] {
            XCTAssertThrowsError(try URLNormalizer.validatedForIngestion(url), "\(url) must be rejected") {
                guard case URLNormalizer.ValidationError.unsupportedScheme = $0 else {
                    return XCTFail("expected unsupportedScheme for \(url), got \($0)")
                }
            }
        }
    }

    // MARK: - Malformed / empty

    func testEmptyRejected() {
        XCTAssertThrowsError(try URLNormalizer.validatedForIngestion("   ")) {
            XCTAssertEqual($0 as? URLNormalizer.ValidationError, .empty)
        }
    }

    func testSchemelessStringRejected() {
        // URL(string:) would accept this as a relative URL; the policy must not.
        XCTAssertThrowsError(try URLNormalizer.validatedForIngestion("example.com/jobs")) {
            guard case URLNormalizer.ValidationError.unsupportedScheme = $0 else {
                return XCTFail("expected unsupportedScheme, got \($0)")
            }
        }
    }

    func testHTTPWithoutHostRejected() {
        XCTAssertThrowsError(try URLNormalizer.validatedForIngestion("https://")) {
            XCTAssertEqual($0 as? URLNormalizer.ValidationError, .malformed)
        }
    }
}
