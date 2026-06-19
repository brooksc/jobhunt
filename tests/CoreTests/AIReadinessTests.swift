import XCTest
@testable import JobhuntCore

/// TASK-512: the shared readiness rule used by both the queue's provider gate and the UI nudge.
/// An empty model is "not configured" for every provider, so the queue keeps work queued behind the
/// setup notice instead of running and failing with `noModelSelected`.
final class AIReadinessTests: XCTestCase {
    func testLocalProvider_emptyModel_notConfigured() {
        XCTAssertFalse(AIReadiness.isConfigured(provider: "lmstudio", model: "", apiKey: ""))
    }

    func testLocalProvider_whitespaceModel_notConfigured() {
        XCTAssertFalse(AIReadiness.isConfigured(provider: "lmstudio", model: "   ", apiKey: ""))
    }

    func testLocalProvider_withModel_noKeyRequired_configured() {
        XCTAssertTrue(AIReadiness.isConfigured(provider: "lmstudio", model: "local-model", apiKey: ""))
    }

    func testHostedProvider_withModel_missingKey_notConfigured() {
        XCTAssertFalse(AIReadiness.isConfigured(provider: "openai", model: "gpt-4o", apiKey: ""))
    }

    func testHostedProvider_emptyModel_notConfigured() {
        // Even with a key, no model means not ready (the gap that previously failed the queue).
        XCTAssertFalse(AIReadiness.isConfigured(provider: "openai", model: "", apiKey: "sk-test"))
    }

    func testHostedProvider_withModelAndKey_configured() {
        XCTAssertTrue(AIReadiness.isConfigured(provider: "openai", model: "gpt-4o", apiKey: "sk-test"))
    }
}
