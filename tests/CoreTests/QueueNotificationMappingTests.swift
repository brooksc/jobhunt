import XCTest
@testable import JobhuntCore

/// The event→notification CONTENT mapping (TASK-542). Catches "forgot to notify", wrong copy, wrong
/// deep-link, or a re-introduced batched-event notification. (OS delivery isn't unit-testable —
/// verify that via Settings → Debug → Send Test Notification.)
final class QueueNotificationMappingTests: XCTestCase {
    func testAuthenticationFailed_isActionableAndDeepLinksToAISettings() {
        let n = QueueEvent.authenticationFailed(statusCode: 401).notification
        XCTAssertEqual(n?.id, "auth-failed")
        XCTAssertTrue(n?.body.contains("401") ?? false, "should include the status code")
        XCTAssertTrue(n?.body.localizedCaseInsensitiveContains("key") ?? false, "should mention the key")
        XCTAssertEqual(n?.navigate, "settings-ai")
        XCTAssertEqual(n?.requestsAttention, true)
    }

    func testAutoPaused_deepLinksToQueueAndRequestsAttention() {
        let n = QueueEvent.autoPaused.notification
        XCTAssertEqual(n?.id, "queue-auto-paused")
        XCTAssertEqual(n?.navigate, "llmQueue")
        XCTAssertEqual(n?.requestsAttention, true)
    }

    func testProviderNotConfigured_deepLinksToAISettings() {
        let n = QueueEvent.providerNotConfigured.notification
        XCTAssertEqual(n?.id, "provider-not-configured")
        XCTAssertEqual(n?.navigate, "settings-ai")
    }

    func testQueueError_carriesTheSanitizedMessage() {
        let n = QueueEvent.queueError("could not read the queue").notification
        XCTAssertEqual(n?.id, "queue-error")
        XCTAssertEqual(n?.body, "could not read the queue")
        XCTAssertEqual(n?.navigate, "llmQueue")
    }

    /// jobReady/processingComplete are batched/summarized by the app layer — they must NOT each
    /// produce a standalone notification here.
    func testBatchedEvents_haveNoStandaloneNotification() {
        XCTAssertNil(QueueEvent.jobReady(jobNumber: 1, title: "x", fitScore: 80).notification)
        XCTAssertNil(QueueEvent.processingComplete(processed: 3, failed: 1).notification)
    }
}
