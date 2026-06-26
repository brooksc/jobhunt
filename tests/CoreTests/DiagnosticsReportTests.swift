import XCTest
@testable import JobhuntCore

final class DiagnosticsReportTests: XCTestCase {
    func testIncludesProviderModelAndCountsVerbatim() {
        let text = DiagnosticsReport.text(
            appVersion: "1.0.4", buildNumber: "2606251842", osVersion: "macOS 26.0",
            provider: "anthropic", model: "claude-opus",
            consentGranted: true, queuePaused: false,
            serverRunning: true, serverError: nil,
            queued: 3, processing: 1, failed: 2,
            recentErrors: []
        )
        XCTAssertTrue(text.contains("App version:        1.0.4 (2606251842)"))
        XCTAssertTrue(text.contains("Provider:           anthropic"))
        XCTAssertTrue(text.contains("Model:              claude-opus"))
        XCTAssertTrue(text.contains("Status:             running"))
        XCTAssertTrue(text.contains("Queued:             3"))
        XCTAssertTrue(text.contains("Processing:         1"))
        XCTAssertTrue(text.contains("Failed:             2"))
        XCTAssertTrue(text.contains("(none)"), "empty recent errors should render (none)")
    }

    // The report must redact secrets in the free-text fields (serverError, recent error messages)
    // so the copied blob is safe to paste into a public issue (TASK-550–553).
    func testRedactsSecretsInFreeTextFields() {
        let text = DiagnosticsReport.text(
            appVersion: "1", buildNumber: "1", osVersion: "macOS",
            provider: "openai", model: "gpt",
            consentGranted: false, queuePaused: true,
            serverRunning: false,
            serverError: "bind failed at /Users/alice/Library/Application Support/secret.store",
            queued: 0, processing: 0, failed: 0,
            recentErrors: [
                .init(timestamp: Date(timeIntervalSince1970: 0),
                      message: "auth failed: Bearer sk-ABCD1234EFGH5678")
            ]
        )
        XCTAssertFalse(text.contains("/Users/alice/Library"), "file paths must be redacted")
        XCTAssertFalse(text.contains("sk-ABCD1234EFGH5678"), "API keys/tokens must be redacted")
        XCTAssertTrue(text.contains("[redacted]"))
        XCTAssertTrue(text.contains("Status:             stopped"))
    }
}
