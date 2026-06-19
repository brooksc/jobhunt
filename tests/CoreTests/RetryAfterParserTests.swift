import XCTest
@testable import JobhuntCore

/// TASK-463: Retry-After header / 429-body parsing.
final class RetryAfterParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testHeaderDeltaSeconds() {
        XCTAssertEqual(RetryAfterParser.parse(header: "30", body: nil, now: now), 30)
        XCTAssertEqual(RetryAfterParser.parse(header: "  12 ", body: nil, now: now), 12)
    }

    func testHeaderHTTPDate() {
        // 60s after `now` (1_700_000_060 = 2023-11-14T22:14:20Z).
        let value = "Tue, 14 Nov 2023 22:14:20 GMT"
        let result = RetryAfterParser.parse(header: value, body: nil, now: now)
        XCTAssertEqual(result ?? -1, 60, accuracy: 1)
    }

    func testHeaderTakesPrecedenceOverBody() {
        let result = RetryAfterParser.parse(header: "5", body: #"{"retryDelay":"99s"}"#, now: now)
        XCTAssertEqual(result, 5)
    }

    func testGeminiRetryDelayBody() {
        let body = #"{"error":{"code":429,"details":[{"@type":"...RetryInfo","retryDelay":"42s"}]}}"#
        XCTAssertEqual(RetryAfterParser.parse(header: nil, body: body, now: now), 42)
    }

    func testOpenAIStyleBodyHints() {
        XCTAssertEqual(RetryAfterParser.parse(header: nil, body: "Please retry in 20 seconds.", now: now), 20)
        XCTAssertEqual(RetryAfterParser.parse(header: nil, body: "try again in 1.5s", now: now), 1.5)
    }

    func testNilWhenNoSignal() {
        XCTAssertNil(RetryAfterParser.parse(header: nil, body: nil, now: now))
        XCTAssertNil(RetryAfterParser.parse(header: "", body: "rate limited, slow down", now: now))
    }

    func testNegativePastDateClampedToZero() {
        let past = "Mon, 13 Nov 2023 00:00:00 GMT" // before `now`
        XCTAssertEqual(RetryAfterParser.parse(header: past, body: nil, now: now), 0)
    }
}

/// TASK-463: QueueActor backoff honors Retry-After for 429s.
final class QueueBackoffTests: XCTestCase {
    func testRateLimitedHonorsRetryAfterClamped() {
        let err = LLMProviderError.rateLimited(retryAfter: 12)
        XCTAssertEqual(QueueActor.backoffMs(for: err, attempt: 0), 12000)
        // Clamp to maxRetryAfterSeconds.
        let huge = LLMProviderError.rateLimited(retryAfter: 9999)
        XCTAssertEqual(
            QueueActor.backoffMs(for: huge, attempt: 0),
            Int(QueueActor.maxRetryAfterSeconds * 1000)
        )
    }

    func testRateLimitedWithoutRetryAfterUsesExponential() {
        // No advised delay → falls back to generic exponential backoff.
        let err = LLMProviderError.rateLimited(retryAfter: nil)
        XCTAssertEqual(QueueActor.backoffMs(for: err, attempt: 2), 4000)
    }

    func testNonRateLimitedUsesExponentialBackoff() {
        let err = LLMProviderError.httpError(statusCode: 500, body: "boom")
        XCTAssertEqual(QueueActor.backoffMs(for: err, attempt: 0), 1000)
        XCTAssertEqual(QueueActor.backoffMs(for: err, attempt: 3), 8000)
        // Capped at 30s.
        XCTAssertEqual(QueueActor.backoffMs(for: err, attempt: 20), 30000)
    }
}
