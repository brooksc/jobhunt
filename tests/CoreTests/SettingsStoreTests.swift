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

/// In-memory keychain fake (TASK-569) — lets tests drive a read failure, which the real Keychain
/// can't be forced to return on demand. `readFailure` is thrown from `read` when non-nil.
private struct FakeKeychain: KeychainAccess {
    var items: [String: String] = [:]
    var readFailure: OSStatus?

    func set(_: String, forKey _: String) throws {}
    func delete(_: String) throws {}
    func read(_ key: String) throws -> String? {
        if let readFailure { throw KeychainError.readFailed(readFailure) }
        return items[key]
    }
}

@MainActor
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

    func testSetAndGetString() throws {
        try store.set("openai", forKey: SettingsKey.llmProvider)
        XCTAssertEqual(store.string(forKey: SettingsKey.llmProvider), "openai")
    }

    func testSetAndGetBool() {
        store.setBool(true, forKey: SettingsKey.llmQueuePaused)
        XCTAssertTrue(store.bool(forKey: SettingsKey.llmQueuePaused))
        store.setBool(false, forKey: SettingsKey.llmQueuePaused)
        XCTAssertFalse(store.bool(forKey: SettingsKey.llmQueuePaused))
    }

    // MARK: - Last sidebar selection (view restore)

    func testLastSidebarSelection_defaultsEmpty() {
        XCTAssertEqual(store.lastSidebarSelection, "")
    }

    func testLastSidebarSelection_roundTrips() {
        store.lastSidebarSelection = "jobs:pursuing"
        XCTAssertEqual(store.lastSidebarSelection, "jobs:pursuing")
    }

    func testSetAndGetInt() {
        store.setInt(600, forKey: SettingsKey.llmTimeout)
        XCTAssertEqual(store.int(forKey: SettingsKey.llmTimeout), 600)
    }

    func testSettingPersistedToStore() throws {
        try store.set("anthropic", forKey: SettingsKey.llmProvider)
        let fetched = try context.fetch(FetchDescriptor<Setting>())
        XCTAssertTrue(fetched.contains { $0.key == SettingsKey.llmProvider && $0.value == "anthropic" })
    }

    func testSettingUpdatedNotDuplicated() throws {
        try store.set("openai", forKey: SettingsKey.llmProvider)
        try store.set("anthropic", forKey: SettingsKey.llmProvider)
        let fetched = try context.fetch(FetchDescriptor<Setting>())
        let providerSettings = fetched.filter { $0.key == SettingsKey.llmProvider }
        XCTAssertEqual(providerSettings.count, 1)
        XCTAssertEqual(providerSettings.first?.value, "anthropic")
    }

    // MARK: - Keychain (API keys must NOT go to SwiftData)

    func testAPIKeyNotInSwiftData() throws {
        try store.setAPIKey("sk-test-key", forProvider: "openai")
        let fetched = try context.fetch(FetchDescriptor<Setting>())
        XCTAssertFalse(fetched.contains { $0.key.hasPrefix("llm_api_key") })
    }

    func testAPIKeyRoundTripKeychain() throws {
        try store.setAPIKey("sk-test-openai", forProvider: "openai")
        XCTAssertEqual(store.apiKey(forProvider: "openai"), "sk-test-openai")
        // Clean up
        try store.setAPIKey("", forProvider: "openai")
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
        XCTAssertEqual(
            keychain.get("migrateTest"),
            "v2",
            "delete+add migration must preserve the latest value"
        )
    }

    /// kSecAttrSynchronizable=false is set on every add. Verify indirectly: re-reading the item
    /// without specifying kSecAttrSynchronizable should still find it (the default search
    /// excludes synced items, so a non-synced item is found by default queries).
    func testKeychainStore_nonSyncedItem_foundByDefaultQuery() throws {
        let keychain = KeychainStore(service: "com.jobhunt-app.test.\(UUID().uuidString)")
        defer { try? keychain.delete("syncTest") }
        try keychain.set("mysecret", forKey: "syncTest")
        XCTAssertEqual(
            keychain.get("syncTest"),
            "mysecret",
            "Non-synced item must be readable by the default (non-synced) search"
        )
    }

    // MARK: - TASK-569: distinguish missing key from Keychain read failure

    func testAPIKeyAvailability_missingWhenNotFound() {
        let s = SettingsStore(modelContext: context, keychain: FakeKeychain())
        XCTAssertEqual(s.apiKeyAvailability(forProvider: "openai"), .missing)
        XCTAssertEqual(s.apiKey(forProvider: "openai"), "", "missing key reads as empty")
    }

    func testAPIKeyAvailability_presentWhenStored() {
        let fake = FakeKeychain(items: ["llm_api_key_openai": "sk-test"])
        let s = SettingsStore(modelContext: context, keychain: fake)
        XCTAssertEqual(s.apiKeyAvailability(forProvider: "openai"), .present)
        XCTAssertEqual(s.apiKey(forProvider: "openai"), "sk-test")
    }

    func testAPIKeyAvailability_unavailableOnReadFailure() {
        // A stored key that the Keychain refuses to return (e.g. -25308 errSecInteractionNotAllowed)
        // must be reported as unavailable-with-status, NOT collapsed to "missing".
        let fake = FakeKeychain(items: ["llm_api_key_openai": "sk-test"], readFailure: errSecInteractionNotAllowed)
        let s = SettingsStore(modelContext: context, keychain: fake)
        XCTAssertEqual(s.apiKeyAvailability(forProvider: "openai"), .unavailable(errSecInteractionNotAllowed))
        // The convenience getter still degrades to "" so callers that can't act on the error don't crash.
        XCTAssertEqual(s.apiKey(forProvider: "openai"), "")
    }

    func testKeychainStore_read_notFoundReturnsNil() throws {
        let keychain = KeychainStore(service: "com.jobhunt-app.test.\(UUID().uuidString)")
        XCTAssertNil(try keychain.read("never-stored"), "errSecItemNotFound is a normal absence, not an error")
    }

    // MARK: - Consent logic

    func testLocalhostProviderAutoConsented() {
        XCTAssertTrue(ConsentHelper.isConsented(provider: "lmstudio", settings: store))
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

    func testQueuePausedMutationVisibleViaClosures() async {
        var paused = store.llmQueuePaused

        let queue = QueueActor(
            store: BackgroundStore(modelContainer: container),
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { await self.store.extractionSettings() },
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

    /// TASK-144 regression: fetchLimit on LLMRequest returns a bounded slice even with large history.
    func testBoundedLLMRequestFetchReturnsAtMostLimit() async throws {
        let bgStore = BackgroundStore(modelContainer: container)
        // Insert 20 LLMRequests
        let requests = (1 ... 20).map { i -> LLMRequest in
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
        let times = fetched.compactMap(\.createdAt)
        XCTAssertTrue(zip(times, times.dropFirst()).allSatisfy { $0 >= $1 }, "Results must be sorted newest first")
    }

    func testBackgroundStoreBatchInsert() async throws {
        let bgStore = BackgroundStore(modelContainer: container)
        let jobs = (1 ... 5).map { Job(jobNumber: $0, company: "Batch\($0)") }
        try await bgStore.insertBatch(jobs)

        let fetched = try context.fetch(FetchDescriptor<Job>())
        XCTAssertGreaterThanOrEqual(fetched.count, 5)
    }

    // MARK: - TASK-388: load-failure recovery state

    //
    // NOTE: the actual load-FAILURE path (loadError set, writes blocked) can't be unit-tested —
    // SwiftData's fetch doesn't throw on demand and BackgroundStore/ModelContext has no
    // failure-injection seam. The behavior is exercised only on a real store-read failure. This
    // covers the readable/recovered baseline.

    /// Baseline / recovered behavior: a readable store loads cleanly, persists, and reload keeps
    /// values and the cleared recovery state.
    func testNormalLoad_persistsAndSurvivesReloadAndReopen() {
        XCTAssertNil(store.loadError)
        store.llmBaseURL = "https://saved.example.com"

        store.reload()
        XCTAssertNil(store.loadError, "Reload on a readable store keeps the cleared recovery state")
        XCTAssertEqual(store.llmBaseURL, "https://saved.example.com")

        // A fresh store on the same context reads the persisted value back.
        let reopened = SettingsStore(modelContext: context)
        XCTAssertEqual(reopened.llmBaseURL, "https://saved.example.com")
    }
}

// MARK: - ConsentHelper snapshot-based tests (QueueActor path)

// TASK-124 / TASK-131 regression: cloud providers blocked without consent; local always allowed.

@MainActor
final class ConsentHelperSnapshotTests: XCTestCase {
    // Tests the overload used inside QueueActor.processExtractRequest:
    //   ConsentHelper.isConsented(provider:baseURL:consentGranted:)

    func testAlwaysLocalProvidersIgnoreConsentFlag() {
        for provider in ["lmstudio"] {
            XCTAssertTrue(
                ConsentHelper.isConsented(provider: provider, baseURL: "", consentGranted: false),
                "\(provider) must be allowed without consent (always local)"
            )
            XCTAssertTrue(ConsentHelper.isConsented(provider: provider, baseURL: "", consentGranted: true))
        }
    }

    func testCloudProviderBlockedWithoutConsent() {
        for provider in ["openai", "anthropic", "google", "openrouter"] {
            XCTAssertFalse(
                ConsentHelper.isConsented(provider: provider, baseURL: "", consentGranted: false),
                "\(provider) must be blocked when consentGranted=false"
            )
        }
    }

    func testCloudProviderAllowedWithConsent() {
        for provider in ["openai", "anthropic", "google", "openrouter"] {
            XCTAssertTrue(
                ConsentHelper.isConsented(provider: provider, baseURL: "", consentGranted: true),
                "\(provider) must be allowed when consentGranted=true"
            )
        }
    }

    func testCustomProviderWithLoopbackURLAllowedWithoutConsent() {
        for url in ["http://127.0.0.1:1234", "http://localhost:8080", "http://[::1]:5000"] {
            XCTAssertTrue(
                ConsentHelper.isConsented(provider: "custom", baseURL: url, consentGranted: false),
                "custom provider on loopback URL \(url) must be allowed without consent"
            )
        }
    }

    func testCustomProviderWithRemoteURLRequiresConsent() {
        let remoteURL = "https://api.example.com"
        XCTAssertFalse(
            ConsentHelper.isConsented(provider: "custom", baseURL: remoteURL, consentGranted: false),
            "custom provider on remote URL must require consent"
        )
        XCTAssertTrue(
            ConsentHelper.isConsented(provider: "custom", baseURL: remoteURL, consentGranted: true),
            "custom provider on remote URL must be allowed when consent is granted"
        )
    }
}

/// A keychain that always refuses the write, so the failure path is exercised rather than assumed.
private struct RefusingKeychain: KeychainAccess {
    func set(_: String, forKey _: String) throws {
        throw KeychainError.addFailed(-25299)
    }

    func read(_: String) throws -> String? {
        nil
    }

    func delete(_: String) throws {
        throw KeychainError.deleteFailed(-25299)
    }
}

/// A failed keychain write used to be indistinguishable from a successful one: `set` caught the
/// error, set `keychainWriteError` for the UI, and returned normally — so a restore or key rotation
/// was told the key had been stored when it hadn't.
@MainActor
final class SettingsStoreKeychainFailureTests: XCTestCase {
    private func store() throws -> SettingsStore {
        let container = try ModelContainer(
            for: Schema(SchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SettingsStore(modelContext: ModelContext(container), keychain: RefusingKeychain())
    }

    func testSetThrowsWhenTheKeychainWriteFails() throws {
        let s = try store()
        XCTAssertThrowsError(try s.set("sk-live-123", forKey: SettingsKey.llmAPIKeyOpenAI))
    }

    func testSetAPIKeyThrowsWhenTheKeychainWriteFails() throws {
        let s = try store()
        XCTAssertThrowsError(try s.setAPIKey("sk-live-123", forProvider: "openai"))
    }

    /// The throw is additional, not a replacement — the UI still reads this flag.
    func testKeychainWriteErrorIsStillSetForTheUI() throws {
        let s = try store()
        XCTAssertThrowsError(try s.setAPIKey("sk-live-123", forProvider: "openai"))
        XCTAssertNotNil(s.keychainWriteError)
    }

    /// Ordinary settings share the entry point and must not become throwing in practice.
    func testNonKeychainSettingsStillWriteCleanly() throws {
        let s = try store()
        try s.set("dark", forKey: "appearance")
        XCTAssertEqual(s.string(forKey: "appearance"), "dark")
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

@MainActor
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

    // These exercise the manager through its URL seam so they never touch the real
    // ~/.jobhunt-mcp-token (TASK-530).

    func testGenerateReadDeleteRoundTrip() throws {
        let token = try MCPTokenManager.generateAndWrite(at: testURL)
        XCTAssertFalse(token.isEmpty)
        XCTAssertEqual(MCPTokenManager.read(at: testURL), token)

        MCPTokenManager.delete(at: testURL)
        XCTAssertNil(MCPTokenManager.read(at: testURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testURL.path))
    }

    func testGenerateAndWriteSetsOwnerOnlyPermissions() throws {
        let token = try MCPTokenManager.generateAndWrite(at: testURL)
        XCTAssertFalse(token.isEmpty)
        let perms = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: testURL.path)[.posixPermissions] as? Int
        )
        XCTAssertEqual(perms & 0o077, 0, "generated token file must be owner-only (0600)")
        XCTAssertNotNil(MCPTokenManager.read(at: testURL), "owner-only token should be readable")
    }

    func testReadRejectsFilesWithBroadPermissions() throws {
        try "tok".write(to: testURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: testURL.path)
        XCTAssertNil(MCPTokenManager.read(at: testURL), "group/world-readable token must be rejected")
    }

    /// TASK-530 AC#3: a failed write leaves no misleading token file behind.
    func testFailedGenerationLeavesNoFile() throws {
        let bad = testURL.appendingPathComponent("no-such-dir").appendingPathComponent("token")
        XCTAssertThrowsError(try MCPTokenManager.generateAndWrite(at: bad))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bad.path))
    }

    func testDeleteMissingFileIsNoOp() {
        MCPTokenManager.delete(at: testURL) // must not crash
        XCTAssertNil(MCPTokenManager.read(at: testURL))
    }

    /// TASK-479/388 AC#4: a settings load failure sets loadError and gates persistence.
    func testLoadFailure_setsLoadErrorAndSkipsPersistence() throws {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)
        struct FakeLoadError: Error {}
        settings.loadFault = FakeLoadError()
        settings.reload()
        XCTAssertNotNil(settings.loadError, "load failure must set loadError")

        // A write while in the load-failure recovery state must NOT persist (could clobber unread
        // stored values), though the in-memory cache updates for the session.
        try settings.set("should-not-persist", forKey: SettingsKey.preferredLocations)
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<Setting>(
            predicate: #Predicate { $0.key == "preferred_locations" }
        ))
        XCTAssertTrue(
            rows.allSatisfy { $0.value != "should-not-persist" },
            "write must not persist while in load-failure recovery state"
        )
    }
}
