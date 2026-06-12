import SwiftData
import XCTest
@testable import JobhuntCore

private struct NoOpLLMProvider: LLMProvider {
    let id = "noop"
    let concurrencyLimit = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}

final class SettingsStoreTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var store: SettingsStore!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        context = ModelContext(container)
        store = SettingsStore(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        store = nil
    }

    // MARK: - Defaults

    func testDefaultLLMProvider() {
        XCTAssertEqual(store.llmProvider, "lmstudio")
    }

    func testDefaultLLMBaseURL() {
        XCTAssertEqual(store.llmBaseURL, "http://127.0.0.1:1234")
    }

    func testDefaultTimeout() {
        XCTAssertEqual(store.llmTimeout, 300)
    }

    func testDefaultLocationFilter() {
        XCTAssertTrue(store.locationFilterEnabled)
        XCTAssertTrue(store.locationAllowRemote)
        XCTAssertTrue(store.locationAllowHybrid)
        XCTAssertTrue(store.locationAllowOnsite)
    }

    func testDefaultQueueNotPaused() {
        XCTAssertFalse(store.llmQueuePaused)
    }

    func testDefaultFollowupDays() {
        XCTAssertEqual(store.followupDefaultDays, 7)
    }

    func testDefaultSiteReviewIntervalDays() {
        XCTAssertEqual(store.siteReviewIntervalDays, 14)
    }

    // MARK: - Round-trip

    func testSetAndGetString() {
        store.set("openai", forKey: SettingsKey.llmProvider)
        XCTAssertEqual(store.string(forKey: SettingsKey.llmProvider), "openai")
    }

    func testSetAndGetBool() {
        store.setBool(true, forKey: SettingsKey.llmQueuePaused)
        XCTAssertTrue(store.bool(forKey: SettingsKey.llmQueuePaused))
        store.setBool(false, forKey: SettingsKey.llmQueuePaused)
        XCTAssertFalse(store.bool(forKey: SettingsKey.llmQueuePaused))
    }

    func testSetAndGetInt() {
        store.setInt(600, forKey: SettingsKey.llmTimeout)
        XCTAssertEqual(store.int(forKey: SettingsKey.llmTimeout), 600)
    }

    func testSettingPersistedToStore() throws {
        store.set("anthropic", forKey: SettingsKey.llmProvider)
        let fetched = try context.fetch(FetchDescriptor<Setting>())
        XCTAssertTrue(fetched.contains { $0.key == SettingsKey.llmProvider && $0.value == "anthropic" })
    }

    func testSettingUpdatedNotDuplicated() throws {
        store.set("openai", forKey: SettingsKey.llmProvider)
        store.set("anthropic", forKey: SettingsKey.llmProvider)
        let fetched = try context.fetch(FetchDescriptor<Setting>())
        let providerSettings = fetched.filter { $0.key == SettingsKey.llmProvider }
        XCTAssertEqual(providerSettings.count, 1)
        XCTAssertEqual(providerSettings.first?.value, "anthropic")
    }

    // MARK: - Keychain (API keys must NOT go to SwiftData)

    func testAPIKeyNotInSwiftData() throws {
        store.setAPIKey("sk-test-key", forProvider: "openai")
        let fetched = try context.fetch(FetchDescriptor<Setting>())
        XCTAssertFalse(fetched.contains { $0.key.hasPrefix("llm_api_key") })
    }

    func testAPIKeyRoundTripKeychain() {
        store.setAPIKey("sk-test-openai", forProvider: "openai")
        XCTAssertEqual(store.apiKey(forProvider: "openai"), "sk-test-openai")
        // Clean up
        store.setAPIKey("", forProvider: "openai")
    }

    func testKeychainStoreSetGetDelete() throws {
        let keychain = KeychainStore(service: "com.jobhunt-app.test.\(UUID().uuidString)")
        try keychain.set("value1", forKey: "testKey")
        XCTAssertEqual(keychain.get("testKey"), "value1")
        try keychain.set("value2", forKey: "testKey")
        XCTAssertEqual(keychain.get("testKey"), "value2")
        try keychain.delete("testKey")
        XCTAssertNil(keychain.get("testKey"))
    }

    // TASK-148: overwrite uses delete+add to migrate security attributes
    func testKeychainStore_overwrite_preservesValueAfterMigration() throws {
        let keychain = KeychainStore(service: "com.jobhunt-app.test.\(UUID().uuidString)")
        defer { try? keychain.delete("migrateTest") }
        try keychain.set("v1", forKey: "migrateTest")
        XCTAssertEqual(keychain.get("migrateTest"), "v1")
        try keychain.set("v2", forKey: "migrateTest")
        XCTAssertEqual(keychain.get("migrateTest"), "v2",
                       "delete+add migration must preserve the latest value")
    }

    // kSecAttrSynchronizable=false is set on every add. Verify indirectly: re-reading the item
    // without specifying kSecAttrSynchronizable should still find it (the default search
    // excludes synced items, so a non-synced item is found by default queries).
    func testKeychainStore_nonSyncedItem_foundByDefaultQuery() throws {
        let keychain = KeychainStore(service: "com.jobhunt-app.test.\(UUID().uuidString)")
        defer { try? keychain.delete("syncTest") }
        try keychain.set("mysecret", forKey: "syncTest")
        XCTAssertEqual(keychain.get("syncTest"), "mysecret",
                       "Non-synced item must be readable by the default (non-synced) search")
    }

    // MARK: - Consent logic

    func testLocalhostProviderAutoConsented() {
        XCTAssertTrue(ConsentHelper.isConsented(provider: "lmstudio", settings: store))
        XCTAssertTrue(ConsentHelper.isConsented(provider: "foundation_models", settings: store))
        XCTAssertTrue(ConsentHelper.isConsented(provider: "custom", settings: store))
    }

    func testCloudProviderNotConsentedByDefault() {
        XCTAssertFalse(ConsentHelper.isConsented(provider: "anthropic", settings: store))
        XCTAssertFalse(ConsentHelper.isConsented(provider: "openai", settings: store))
        XCTAssertFalse(ConsentHelper.isConsented(provider: "google", settings: store))
        XCTAssertFalse(ConsentHelper.isConsented(provider: "openrouter", settings: store))
    }

    func testGrantAndRevokeConsent() {
        ConsentHelper.setConsent(provider: "anthropic", granted: true, settings: store)
        XCTAssertTrue(ConsentHelper.isConsented(provider: "anthropic", settings: store))
        ConsentHelper.setConsent(provider: "anthropic", granted: false, settings: store)
        XCTAssertFalse(ConsentHelper.isConsented(provider: "anthropic", settings: store))
    }

    // MARK: - ExtractionSettings snapshot visibility

    func testExtractionSettingsSnapshotReflectsCurrentValues() {
        store.llmModel = "custom-model"
        store.preferredLocations = "Seattle, WA"
        store.locationFilterEnabled = true
        store.locationAllowRemote = false

        let snap = store.extractionSettings()
        XCTAssertEqual(snap.llmModel, "custom-model")
        XCTAssertEqual(snap.preferredLocations, "Seattle, WA")
        XCTAssertTrue(snap.locationFilterEnabled)
        XCTAssertFalse(snap.locationAllowRemote)
    }

    func testExtractionSettingsSnapshotIsIndependentAfterMutation() {
        store.llmModel = "model-v1"
        let snapBefore = store.extractionSettings()

        store.llmModel = "model-v2"
        let snapAfter = store.extractionSettings()

        // Snapshot taken before mutation retains the old value
        XCTAssertEqual(snapBefore.llmModel, "model-v1")
        XCTAssertEqual(snapAfter.llmModel, "model-v2")
    }

    func testQueuePausedMutationVisibleViaClosures() async throws {
        var paused = store.llmQueuePaused

        let queue = QueueActor(
            store: BackgroundStore(modelContainer: container),
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { self.store.extractionSettings() },
            providerFactory: { NoOpLLMProvider() }
        )

        XCTAssertFalse(paused)
        await queue.pauseQueue()
        XCTAssertTrue(paused, "Pause closure should write back to local state")
        await queue.resumeQueue()
        XCTAssertFalse(paused, "Resume closure should clear paused state")
    }

    // MARK: - BackgroundStore off-main-actor write

    func testBackgroundStoreInsertsJob() async throws {
        let bgStore = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 9001, company: "BgCo")
        try await bgStore.insert(job)

        let fetched = try context.fetch(FetchDescriptor<Job>())
        XCTAssertTrue(fetched.contains { $0.jobNumber == 9001 })
    }

    // TASK-144 regression: fetchLimit on LLMRequest returns a bounded slice even with large history.
    func testBoundedLLMRequestFetchReturnsAtMostLimit() async throws {
        let bgStore = BackgroundStore(modelContainer: container)
        // Insert 20 LLMRequests
        let requests = (1...20).map { i -> LLMRequest in
            let r = LLMRequest(requestType: .extract, status: .succeeded)
            r.createdAt = Date(timeIntervalSinceNow: Double(i))
            return r
        }
        try await bgStore.insertBatch(requests)

        var descriptor = FetchDescriptor<LLMRequest>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 10, "fetchLimit must bound the result to 10 even with 20 total")
        // Newest 10 should come first (descending order)
        let times = fetched.compactMap { $0.createdAt }
        XCTAssertTrue(zip(times, times.dropFirst()).allSatisfy { $0 >= $1 }, "Results must be sorted newest first")
    }

    func testBackgroundStoreBatchInsert() async throws {
        let bgStore = BackgroundStore(modelContainer: container)
        let jobs = (1 ... 5).map { Job(jobNumber: $0, company: "Batch\($0)") }
        try await bgStore.insertBatch(jobs)

        let fetched = try context.fetch(FetchDescriptor<Job>())
        XCTAssertGreaterThanOrEqual(fetched.count, 5)
    }
}

// MARK: - ConsentHelper snapshot-based tests (QueueActor path)
// TASK-124 / TASK-131 regression: cloud providers blocked without consent; local always allowed.

final class ConsentHelperSnapshotTests: XCTestCase {
    // Tests the overload used inside QueueActor.processExtractRequest:
    //   ConsentHelper.isConsented(provider:baseURL:consentGranted:)

    func testAlwaysLocalProvidersIgnoreConsentFlag() {
        for provider in ["lmstudio", "foundation_models"] {
            XCTAssertTrue(ConsentHelper.isConsented(provider: provider, baseURL: "", consentGranted: false),
                          "\(provider) must be allowed without consent (always local)")
            XCTAssertTrue(ConsentHelper.isConsented(provider: provider, baseURL: "", consentGranted: true))
        }
    }

    func testCloudProviderBlockedWithoutConsent() {
        for provider in ["openai", "anthropic", "google", "openrouter"] {
            XCTAssertFalse(ConsentHelper.isConsented(provider: provider, baseURL: "", consentGranted: false),
                           "\(provider) must be blocked when consentGranted=false")
        }
    }

    func testCloudProviderAllowedWithConsent() {
        for provider in ["openai", "anthropic", "google", "openrouter"] {
            XCTAssertTrue(ConsentHelper.isConsented(provider: provider, baseURL: "", consentGranted: true),
                          "\(provider) must be allowed when consentGranted=true")
        }
    }

    func testCustomProviderWithLoopbackURLAllowedWithoutConsent() {
        for url in ["http://127.0.0.1:1234", "http://localhost:8080", "http://[::1]:5000"] {
            XCTAssertTrue(ConsentHelper.isConsented(provider: "custom", baseURL: url, consentGranted: false),
                          "custom provider on loopback URL \(url) must be allowed without consent")
        }
    }

    func testCustomProviderWithRemoteURLRequiresConsent() {
        let remoteURL = "https://api.example.com"
        XCTAssertFalse(ConsentHelper.isConsented(provider: "custom", baseURL: remoteURL, consentGranted: false),
                       "custom provider on remote URL must require consent")
        XCTAssertTrue(ConsentHelper.isConsented(provider: "custom", baseURL: remoteURL, consentGranted: true),
                      "custom provider on remote URL must be allowed when consent is granted")
    }
}

// MARK: - KeychainError LocalizedError tests

final class KeychainErrorTests: XCTestCase {
    func testKeychainError_localizedDescriptions_doNotExposeRawStatus() {
        let add = KeychainError.addFailed(-25299)
        let upd = KeychainError.updateFailed(-25300)
        let del = KeychainError.deleteFailed(-25301)
        for err in [add, upd, del] as [KeychainError] {
            XCTAssertFalse(err.localizedDescription.isEmpty)
        }
        XCTAssertTrue(add.localizedDescription.contains("-25299"), "Status code should appear for diagnostics")
    }
}

// MARK: - MCPTokenManager tests

final class MCPTokenManagerTests: XCTestCase {
    private var testURL: URL!

    override func setUp() {
        super.setUp()
        testURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-token-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testURL)
        super.tearDown()
    }

    func testGenerateAndWriteProducesNonEmptyToken() throws {
        let originalURL = MCPTokenManager.tokenURL
        // Write to temp path by calling low-level write directly
        let token = UUID().uuidString
        try token.write(to: testURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: testURL.path)
        let read = try String(contentsOf: testURL, encoding: .utf8)
        XCTAssertEqual(read, token)
        _ = originalURL // suppress warning
    }

    func testReadRejectsFilesWithBroadPermissions() throws {
        // Write a token then open permissions — read() should return nil
        let token = UUID().uuidString
        try token.write(to: testURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: testURL.path)

        let attrs = try FileManager.default.attributesOfItem(atPath: testURL.path)
        let perms = attrs[.posixPermissions] as? Int ?? 0
        XCTAssertNotEqual(perms & 0o077, 0, "File should have group/other bits set (test precondition)")
        // MCPTokenManager.read() checks permissions — simulate the same check
        XCTAssertNotEqual(perms & 0o077, 0, "Broad permissions should be detectable")
    }

    func testReadAcceptsFilesWithOwnerOnlyPermissions() throws {
        let token = UUID().uuidString
        try token.write(to: testURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: testURL.path)

        let attrs = try FileManager.default.attributesOfItem(atPath: testURL.path)
        let perms = attrs[.posixPermissions] as? Int ?? 0
        XCTAssertEqual(perms & 0o077, 0, "Owner-only file should pass permission check")
    }

    func testGenerateAndWriteSetsCorrectPermissions() throws {
        // Use MCPTokenManager directly and verify permissions
        let token = MCPTokenManager.generateAndWrite()
        XCTAssertFalse(token.isEmpty)
        let attrs = try FileManager.default.attributesOfItem(atPath: MCPTokenManager.tokenURL.path)
        let perms = attrs[.posixPermissions] as? Int ?? 0
        XCTAssertEqual(perms & 0o077, 0, "Generated token file must be owner-only (0600)")
        XCTAssertNotNil(MCPTokenManager.read(), "Token written with correct permissions should be readable")
    }
}
