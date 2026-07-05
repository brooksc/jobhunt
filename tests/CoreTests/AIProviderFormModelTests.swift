import SwiftData
import XCTest
@testable import JobhuntCore

/// The shared AI-provider form logic (TASK-541) — exercises the rules that previously drifted
/// between the onboarding step and the Settings AI tab. Layout lives in the views; every decision
/// lives in the model and is pinned here.
@MainActor
final class AIProviderFormModelTests: XCTestCase {
    private func makeModel(
        listModels: @escaping AIProviderFormModel.ModelLister = { _, _, _ in [] }
    ) throws -> AIProviderFormModel {
        let container = try ModelContainerFactory.inMemory()
        let settings = SettingsStore(modelContext: ModelContext(container))
        return AIProviderFormModel(settings: settings, listModels: listModels)
    }

    // AC#1: custom loopback needs no key; custom remote does.
    func testCustomLoopbackNeedsNoKey_remoteDoes() throws {
        let model = try makeModel()
        model.selectedProviderID = "custom"
        model.baseURLText = "http://127.0.0.1:1234"
        XCTAssertFalse(model.needsAPIKey, "loopback custom is on-device — no key")
        model.baseURLText = "https://api.example.com/v1"
        XCTAssertTrue(model.needsAPIKey, "remote custom is a cloud endpoint — needs a key")
    }

    // AC#2: a remote custom URL requires consent; a loopback one does not.
    func testRemoteCustomURLTriggersConsent_loopbackDoesNot() throws {
        let model = try makeModel()
        model.selectedProviderID = "custom"
        model.onBaseURLChanged("http://127.0.0.1:1234")
        XCTAssertNil(model.pendingConsent, "loopback custom must not require consent")
        model.onBaseURLChanged("https://remote.example.com")
        XCTAssertEqual(model.pendingConsent?.id, "custom", "remote custom must require consent")
    }

    // AC#2: switching to an unconsented cloud provider requests consent and doesn't apply yet.
    func testSwitchToUnconsentedCloudRequestsConsentAndDefers() throws {
        let model = try makeModel()
        let before = model.selectedProviderID
        model.handleProviderChange(to: "openai")
        XCTAssertEqual(model.pendingConsent?.id, "openai")
        XCTAssertEqual(model.selectedProviderID, before, "provider not applied until consent is granted")
    }

    // AC#3: Test Connection with no model fails fast with a clear message (no network call).
    func testEmptyModelTestConnectionFailsFast() async throws {
        let model = try makeModel()
        model.settings.llmModel = ""
        await model.testConnection()
        guard case let .failure(message) = model.connectionStatus else {
            return XCTFail("expected a failure status, got \(model.connectionStatus)")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("model"), "should tell the user to pick a model")
    }

    // AC#5: API-key whitespace is stripped as it's entered.
    func testAPIKeyWhitespaceIsStripped() throws {
        let model = try makeModel()
        model.selectedProviderID = "openai"
        model.onAPIKeyChanged("  sk-abc123\n")
        XCTAssertEqual(model.apiKeyText, "sk-abc123")
    }

    // TASK-599: the sanitize count bumps only when characters were actually stripped, so the view can
    // re-key the secure field to drop a pasted newline glyph — but ordinary clean input never rebuilds
    // the field (which would drop focus).
    func testAPIKeySanitizeCountBumpsOnlyWhenStripping() throws {
        let model = try makeModel()
        model.selectedProviderID = "openai"

        model.onAPIKeyChanged("sk-clean")
        XCTAssertEqual(model.apiKeySanitizeCount, 0, "clean input must not bump the count")

        model.onAPIKeyChanged("sk-pasted\n")
        XCTAssertEqual(model.apiKeyText, "sk-pasted")
        XCTAssertEqual(model.apiKeySanitizeCount, 1, "a stripped newline must bump the count")

        model.onAPIKeyChanged("  sk with spaces \n")
        XCTAssertEqual(model.apiKeyText, "skwithspaces")
        XCTAssertEqual(model.apiKeySanitizeCount, 2, "another strip must bump again")
    }

    // AC#4: a model fetch that resolves AFTER the user switched providers must not clobber the list.
    func testStaleFetchDoesNotClobberNewerProvider() async throws {
        let entered = AsyncStream.makeStream(of: Void.self)
        var release: CheckedContinuation<Void, Never>?
        let model = try makeModel(listModels: { _, _, _ in
            await withCheckedContinuation { cont in
                release = cont
                entered.continuation.yield(()) // signal *after* the continuation is captured
            }
            return ["stale-model"]
        })
        model.selectedProviderID = "openai"
        let fetch = Task { await model.fetchModels() }

        // Wait until the fetch is actually in-flight, then switch providers before it returns.
        var iterator = entered.stream.makeAsyncIterator()
        _ = await iterator.next()
        model.selectedProviderID = "anthropic"
        release?.resume()
        await fetch.value

        XCTAssertTrue(model.fetchedModels.isEmpty, "the stale provider's result must be discarded")
    }

    /// AC#3 regression: the 401/403 message is actionable.
    func testHTTPFailureMessageMentionsKeyForAuthCodes() {
        let msg = AIProviderFormModel.httpFailureMessage(code: 401, body: #"{"error":{"message":"bad key"}}"#)
        XCTAssertTrue(msg.contains("401"))
        XCTAssertTrue(msg.localizedCaseInsensitiveContains("key"))
        XCTAssertTrue(msg.contains("bad key"), "should surface the provider's own message")
        XCTAssertEqual(AIProviderFormModel.httpFailureMessage(code: 500, body: ""), "HTTP 500")
    }
}
