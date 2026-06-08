import SwiftData
import XCTest
@testable import JobhuntCore

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

    // MARK: - BackgroundStore off-main-actor write

    func testBackgroundStoreInsertsJob() async throws {
        let bgStore = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 9001, company: "BgCo")
        try await bgStore.insert(job)

        let fetched = try context.fetch(FetchDescriptor<Job>())
        XCTAssertTrue(fetched.contains { $0.jobNumber == 9001 })
    }

    func testBackgroundStoreBatchInsert() async throws {
        let bgStore = BackgroundStore(modelContainer: container)
        let jobs = (1 ... 5).map { Job(jobNumber: $0, company: "Batch\($0)") }
        try await bgStore.insertBatch(jobs)

        let fetched = try context.fetch(FetchDescriptor<Job>())
        XCTAssertGreaterThanOrEqual(fetched.count, 5)
    }
}
