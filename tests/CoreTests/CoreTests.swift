import XCTest
@testable import JobhuntCore

/// Raw values are stored in SwiftData and exported via CSV/MCP/extension.
/// Changing them is a breaking migration. Pin them here so a rename becomes a test failure.
final class CoreEnumRawValueTests: XCTestCase {
    func testJobStatusRawValues() {
        XCTAssertEqual(JobStatus.new.rawValue, "new")
        XCTAssertEqual(JobStatus.pursuing.rawValue, "pursuing")
        XCTAssertEqual(JobStatus.applied.rawValue, "applied")
        XCTAssertEqual(JobStatus.interview.rawValue, "interview")
        XCTAssertEqual(JobStatus.offer.rawValue, "offer")
        XCTAssertEqual(JobStatus.rejected.rawValue, "rejected")
        XCTAssertEqual(JobStatus.passed.rawValue, "passed")
        XCTAssertEqual(JobStatus.archived.rawValue, "archived")
        XCTAssertEqual(JobStatus.closed.rawValue, "closed")
        XCTAssertEqual(JobStatus.duplicate.rawValue, "duplicate")
        XCTAssertEqual(JobStatus.expired.rawValue, "expired")
    }

    func testExtractionStatusRawValues() {
        XCTAssertEqual(ExtractionStatus.pending.rawValue, "pending")
        XCTAssertEqual(ExtractionStatus.running.rawValue, "running")
        XCTAssertEqual(ExtractionStatus.succeeded.rawValue, "succeeded")
        XCTAssertEqual(ExtractionStatus.failed.rawValue, "failed")
        XCTAssertEqual(ExtractionStatus.skipped.rawValue, "skipped")
    }

    func testLLMRequestStatusRawValues() {
        XCTAssertEqual(LLMRequestStatus.queued.rawValue, "queued")
        XCTAssertEqual(LLMRequestStatus.retryExhausted.rawValue, "retry_exhausted")
        XCTAssertEqual(SiteState.notReviewed.rawValue, "not_reviewed")
    }
}
