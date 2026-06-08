import Foundation
import Observation
import SwiftData

// Mirrors SETTINGS_DEFAULTS from server/db.js exactly.
private let settingsDefaults: [String: String] = [
    SettingsKey.llmProvider: "lmstudio",
    SettingsKey.llmBaseURL: "http://127.0.0.1:1234",
    SettingsKey.llmModel: "gemma-4-e4b-it-mlx",
    SettingsKey.llmTimeout: "300",
    SettingsKey.siteReviewIntervalDays: "14",
    SettingsKey.followupDefaultDays: "7",
    SettingsKey.jobDescriptionMarkdown: "",
    SettingsKey.preferredLocations: "",
    SettingsKey.preferredMetros: "",
    SettingsKey.locationFilterEnabled: "true",
    SettingsKey.locationAllowRemote: "true",
    SettingsKey.locationAllowHybrid: "true",
    SettingsKey.locationAllowOnsite: "true",
    SettingsKey.llmQueuePaused: "false",
    SettingsKey.llmDebugLevel: "errors",
    SettingsKey.availabilityAutoCheckEnabled: "true",
    SettingsKey.availabilityAutoCheckIntervalDays: "1",
    SettingsKey.availabilityStaleDays: "21",
    SettingsKey.availabilityLastAutoCheckAt: "",
    SettingsKey.llmPriceInput: "0",
    SettingsKey.llmPriceOutput: "0",
    SettingsKey.llmOpenRouterFreeRotate: "false",
    SettingsKey.llmConsentAnthropic: "0",
    SettingsKey.llmConsentGoogle: "0",
    SettingsKey.llmConsentOpenRouter: "0",
    SettingsKey.llmConsentOpenAI: "0"
]

@Observable
public final class SettingsStore {
    private var modelContext: ModelContext
    private var keychain: KeychainStore
    private var cache: [String: String] = [:]

    public init(modelContext: ModelContext, keychain: KeychainStore = KeychainStore()) {
        self.modelContext = modelContext
        self.keychain = keychain
        loadCache()
    }

    // MARK: - Generic accessors

    public func string(forKey key: String) -> String {
        if SettingsKey.keychainKeys.contains(key) {
            return keychain.get(key) ?? ""
        }
        return cache[key] ?? settingsDefaults[key] ?? ""
    }

    public func set(_ value: String, forKey key: String) {
        if SettingsKey.keychainKeys.contains(key) {
            try? keychain.set(value, forKey: key)
            return
        }
        cache[key] = value
        persistToStore(key: key, value: value)
    }

    public func bool(forKey key: String) -> Bool {
        let strVal = string(forKey: key)
        return strVal == "true" || strVal == "1"
    }

    public func setBool(_ value: Bool, forKey key: String) {
        set(value ? "true" : "false", forKey: key)
    }

    public func int(forKey key: String) -> Int {
        Int(string(forKey: key)) ?? 0
    }

    public func setInt(_ value: Int, forKey key: String) {
        set(String(value), forKey: key)
    }

    public func double(forKey key: String) -> Double {
        Double(string(forKey: key)) ?? 0
    }

    public func setDouble(_ value: Double, forKey key: String) {
        set(String(value), forKey: key)
    }

    // MARK: - Typed shortcut properties (most-used settings)

    public var llmProvider: String {
        get { string(forKey: SettingsKey.llmProvider) }
        set { set(newValue, forKey: SettingsKey.llmProvider) }
    }

    public var llmBaseURL: String {
        get { string(forKey: SettingsKey.llmBaseURL) }
        set { set(newValue, forKey: SettingsKey.llmBaseURL) }
    }

    public var llmModel: String {
        get { string(forKey: SettingsKey.llmModel) }
        set { set(newValue, forKey: SettingsKey.llmModel) }
    }

    public var llmTimeout: Int {
        get { int(forKey: SettingsKey.llmTimeout) }
        set { setInt(newValue, forKey: SettingsKey.llmTimeout) }
    }

    public var llmQueuePaused: Bool {
        get { bool(forKey: SettingsKey.llmQueuePaused) }
        set { setBool(newValue, forKey: SettingsKey.llmQueuePaused) }
    }

    public var locationFilterEnabled: Bool {
        get { bool(forKey: SettingsKey.locationFilterEnabled) }
        set { setBool(newValue, forKey: SettingsKey.locationFilterEnabled) }
    }

    public var locationAllowRemote: Bool {
        get { bool(forKey: SettingsKey.locationAllowRemote) }
        set { setBool(newValue, forKey: SettingsKey.locationAllowRemote) }
    }

    public var locationAllowHybrid: Bool {
        get { bool(forKey: SettingsKey.locationAllowHybrid) }
        set { setBool(newValue, forKey: SettingsKey.locationAllowHybrid) }
    }

    public var locationAllowOnsite: Bool {
        get { bool(forKey: SettingsKey.locationAllowOnsite) }
        set { setBool(newValue, forKey: SettingsKey.locationAllowOnsite) }
    }

    public var preferredLocations: String {
        get { string(forKey: SettingsKey.preferredLocations) }
        set { set(newValue, forKey: SettingsKey.preferredLocations) }
    }

    public var preferredMetros: String {
        get { string(forKey: SettingsKey.preferredMetros) }
        set { set(newValue, forKey: SettingsKey.preferredMetros) }
    }

    public var siteReviewIntervalDays: Int {
        get { int(forKey: SettingsKey.siteReviewIntervalDays) }
        set { setInt(newValue, forKey: SettingsKey.siteReviewIntervalDays) }
    }

    public var followupDefaultDays: Int {
        get { int(forKey: SettingsKey.followupDefaultDays) }
        set { setInt(newValue, forKey: SettingsKey.followupDefaultDays) }
    }

    // MARK: - Keychain API key accessors

    public func apiKey(forProvider provider: String) -> String {
        let key = provider == "default" ? SettingsKey.llmAPIKey : "llm_api_key_\(provider)"
        return keychain.get(key) ?? ""
    }

    public func setAPIKey(_ value: String, forProvider provider: String) {
        let key = provider == "default" ? SettingsKey.llmAPIKey : "llm_api_key_\(provider)"
        try? keychain.set(value, forKey: key)
    }

    // MARK: - Private

    private func loadCache() {
        let all = (try? modelContext.fetch(FetchDescriptor<Setting>())) ?? []
        for setting in all {
            cache[setting.key] = setting.value
        }
    }

    private func persistToStore(key: String, value: String) {
        let descriptor = FetchDescriptor<Setting>(predicate: #Predicate { $0.key == key })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.value = value
            existing.updatedAt = Date()
        } else {
            modelContext.insert(Setting(key: key, value: value))
        }
        try? modelContext.save()
    }
}
