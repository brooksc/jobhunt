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

    // TASK-567: cloud consent is part of readiness — a hosted provider with model + key but no
    // consent is NOT configured (so the queue leaves work queued instead of failing it).
    func testHostedProvider_missingConsent_notConfigured() {
        XCTAssertFalse(AIReadiness.isConfigured(
            provider: "openai", model: "gpt-4o", apiKey: "sk-test", baseURL: "", consented: false
        ))
    }

    func testHostedProvider_withConsent_configured() {
        XCTAssertTrue(AIReadiness.isConfigured(
            provider: "openai", model: "gpt-4o", apiKey: "sk-test", baseURL: "", consented: true
        ))
    }

    func testLocalProvider_configuredWhenConsented() {
        // Local providers are always consented (resolved by the convenience); model + no key suffices.
        XCTAssertTrue(AIReadiness.isConfigured(
            provider: "lmstudio", model: "m", apiKey: "", baseURL: "http://127.0.0.1:1234", consented: true
        ))
    }

    // TASK-568: remote custom endpoints need a key; loopback custom does not.
    func testCustomRemote_missingKey_notConfigured() {
        XCTAssertFalse(AIReadiness.isConfigured(
            provider: "custom", model: "m", apiKey: "", baseURL: "https://api.example.com", consented: true
        ))
    }

    func testCustomLoopback_noKey_configured() {
        XCTAssertTrue(AIReadiness.isConfigured(
            provider: "custom", model: "m", apiKey: "", baseURL: "http://127.0.0.1:1234", consented: true
        ))
    }

    func testCustomRemote_withKeyAndConsent_configured() {
        XCTAssertTrue(AIReadiness.isConfigured(
            provider: "custom", model: "m", apiKey: "k", baseURL: "https://api.example.com", consented: true
        ))
    }

    /// The base-URL-aware key policy is shared between the form and readiness (TASK-568).
    func testRequiresAPIKeyPolicy_customRemoteVsLoopback() {
        XCTAssertTrue(LLMProviderFactory.requiresAPIKey(provider: "custom", baseURL: "https://api.example.com"))
        XCTAssertFalse(LLMProviderFactory.requiresAPIKey(provider: "custom", baseURL: "http://127.0.0.1:1234"))
        XCTAssertTrue(LLMProviderFactory.requiresAPIKey(provider: "openai", baseURL: ""))
        XCTAssertFalse(LLMProviderFactory.requiresAPIKey(provider: "lmstudio", baseURL: ""))
    }
}
