import Foundation
import Observation
import SwiftData

/// Mirrors SETTINGS_DEFAULTS from server/db.js exactly.
private let settingsDefaults: [String: String] = [
    SettingsKey.llmProvider: "lmstudio",
    SettingsKey.llmBaseURL: "http://127.0.0.1:1234",
    // No default model — models are loaded dynamically from each provider's API and the user
    // must explicitly choose one (see ModelCatalog). An empty value means "not yet selected".
    SettingsKey.llmModel: "",
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
    SettingsKey.llmOpenRouterFreeRotate: "false",
    SettingsKey.availabilityAutoCheckEnabled: "true",
    SettingsKey.availabilityAutoCheckIntervalDays: "1",
    SettingsKey.availabilityStaleDays: "21",
    SettingsKey.availabilityLastAutoCheckAt: "",
    SettingsKey.llmPriceInput: "0",
    SettingsKey.llmPriceOutput: "0",
    SettingsKey.llmConsentAnthropic: "0",
    SettingsKey.llmConsentGoogle: "0",
    SettingsKey.llmConsentOpenRouter: "0",
    SettingsKey.llmConsentOpenAI: "0",
    SettingsKey.lastSidebarSelection: "",
    SettingsKey.jobsSortKey: "capturedAt",
    SettingsKey.jobsSortAscending: "false"
]

@Observable
public final class SettingsStore {
    private var modelContext: ModelContext
    private var keychain: KeychainStore
    private var cache: [String: String] = [:]
    /// Set when a keychain write fails; cleared on the next successful write.
    public var keychainWriteError: String?
    /// Set when a SwiftData persist fails; cleared on the next successful write.
    /// Contains the key name and error type — never the setting value.
    public var lastSettingsError: String?
    /// Set when the initial load of stored settings failed. While this is non-nil the store is in a
    /// recovery state: reads fall back to defaults but writes are NOT persisted, so a default value
    /// can't overwrite stored settings that merely couldn't be read. Cleared by a successful `reload()`.
    public private(set) var loadError: String?

    public init(modelContext: ModelContext, keychain: KeychainStore = KeychainStore()) {
        self.modelContext = modelContext
        self.keychain = keychain
        loadCache()
        migrateRemovedProviders()
    }

    /// Apple Foundation Models was removed as a provider. Redirect any saved selection to the
    /// default local provider so the app isn't left pointing at a provider that no longer exists.
    private func migrateRemovedProviders() {
        let current = cache[SettingsKey.llmProvider]
        if current == "foundation_models" || current == "apple" {
            set("lmstudio", forKey: SettingsKey.llmProvider)
        }
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
            do {
                try keychain.set(value, forKey: key)
                keychainWriteError = nil
            } catch {
                keychainWriteError = error.localizedDescription
            }
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

    /// The last-viewed sidebar selection, persisted so relaunch restores the same view. Opaque
    /// token serialized by `SidebarItem.persistedID`; "" means none stored yet (default view).
    public var lastSidebarSelection: String {
        get { string(forKey: SettingsKey.lastSidebarSelection) }
        set { set(newValue, forKey: SettingsKey.lastSidebarSelection) }
    }

    /// Persisted Jobs-list sort (review-2 #7). Survives sidebar-selection resets and relaunch.
    /// Stored as the `JobsSortKey` rawValue; the view maps it back to the enum.
    public var jobsSortKey: String {
        get { string(forKey: SettingsKey.jobsSortKey) }
        set { set(newValue, forKey: SettingsKey.jobsSortKey) }
    }

    public var jobsSortAscending: Bool {
        get { bool(forKey: SettingsKey.jobsSortAscending) }
        set { setBool(newValue, forKey: SettingsKey.jobsSortAscending) }
    }

    /// TASK-462: when on (and provider is OpenRouter), rotate over free structured-output models with
    /// failover instead of using the single configured model. Default off.
    public var llmOpenRouterFreeRotate: Bool {
        get { bool(forKey: SettingsKey.llmOpenRouterFreeRotate) }
        set { setBool(newValue, forKey: SettingsKey.llmOpenRouterFreeRotate) }
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

    // MARK: - Per-provider model memory

    /// The model most recently chosen for `provider`, or "" if none has been selected yet.
    /// There is no hardcoded fallback — models come from the provider's API (see ModelCatalog)
    /// and selection is explicit.
    public func modelForProvider(_ provider: String) -> String {
        string(forKey: "llm_model_\(provider)")
    }

    public func setModelForProvider(_ model: String, provider: String) {
        set(model, forKey: "llm_model_\(provider)")
        llmModel = model
    }

    // MARK: - Keychain API key accessors

    public func apiKey(forProvider provider: String) -> String {
        let key = provider == "default" ? SettingsKey.llmAPIKey : "llm_api_key_\(provider)"
        return keychain.get(key) ?? ""
    }

    public func setAPIKey(_ value: String, forProvider provider: String) {
        let key = provider == "default" ? SettingsKey.llmAPIKey : "llm_api_key_\(provider)"
        // Trim pasted whitespace/newlines — a trailing space alone makes a valid key get rejected
        // (e.g. Google returns 401) with no obvious cause.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try keychain.set(trimmed, forKey: key)
            keychainWriteError = nil
        } catch {
            keychainWriteError = error.localizedDescription
        }
    }

    // MARK: - Private

    /// Test-only fault injection (TASK-479): when set, `loadCache`/`reload` treat the load as failed
    /// (SwiftData's fetch can't be made to error on demand). Nil in production.
    public var loadFault: Error?

    private func loadCache() {
        do {
            if let loadFault { throw loadFault }
            let all = try modelContext.fetch(FetchDescriptor<Setting>())
            cache.removeAll()
            for setting in all {
                cache[setting.key] = setting.value
            }
            loadError = nil
        } catch {
            // Couldn't read stored settings. Don't treat defaults as authoritative and — critically —
            // don't let subsequent writes persist defaults over the stored values we failed to read
            // (persistToStore is gated on loadError). Surface a recovery state instead.
            NSLog("SettingsStore: failed to load settings: \(error)")
            loadError = "Couldn't load saved settings (\(type(of: error))). Your preferences weren't read; relaunch to retry."
        }
    }

    /// Re-attempt the initial load — e.g. after a transient store error clears. On success the cache
    /// is repopulated from disk and `loadError` is cleared (re-enabling persistence).
    public func reload() {
        loadCache()
    }

    // MARK: - ExtractionSettings snapshot

    /// Sendable snapshot of the fields needed by ExtractionEngine.
    /// Callers on background actors should use this instead of holding a live SettingsStore reference.
    public func extractionSettings() -> ExtractionSettings {
        let provider = llmProvider
        let baseURL = llmBaseURL
        let consentGranted = ConsentHelper.isConsented(provider: provider, settings: self)
        // Combine manual preferred locations with expanded preferred metros (Electron parity:
        // makeExtractorFromSettings expanded metros into the location context), deduped.
        let manual = preferredLocations
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var combined: [String] = []
        var seen = Set<String>()
        for loc in manual + expandMetros(preferredMetros) where !seen.contains(loc.lowercased()) {
            seen.insert(loc.lowercased())
            combined.append(loc)
        }
        return ExtractionSettings(
            llmModel: llmModel,
            llmProvider: provider,
            llmBaseURL: baseURL,
            consentGranted: consentGranted,
            preferredLocations: combined.joined(separator: ", "),
            locationFilterEnabled: locationFilterEnabled,
            locationAllowRemote: locationAllowRemote,
            locationAllowHybrid: locationAllowHybrid,
            locationAllowOnsite: locationAllowOnsite
        )
    }

    // MARK: - Private

    private func persistToStore(key: String, value: String) {
        // In the load-failure recovery state, the on-disk settings couldn't be read. Persisting now
        // would risk writing a default over a real stored value we never loaded, so skip the write
        // (the in-memory cache still updates for this session). reload() re-enables persistence.
        guard loadError == nil else {
            NSLog("SettingsStore: skipping persist of '\(key)' while in load-failure recovery state")
            return
        }
        let descriptor = FetchDescriptor<Setting>(predicate: #Predicate { $0.key == key })
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.value = value
                existing.updatedAt = Date()
            } else {
                modelContext.insert(Setting(key: key, value: value))
            }
            try modelContext.save()
        } catch {
            NSLog("SettingsStore: failed to persist \(key): \(error)")
            lastSettingsError = "Failed to save '\(key)': \(type(of: error))"
        }
    }
}

// MARK: - ExtractionSettings

/// Sendable snapshot of settings consumed by ExtractionEngine.
/// Capture this once on the main actor before crossing into background actors.
public struct ExtractionSettings: Sendable {
    public let llmModel: String
    public let llmProvider: String
    public let llmBaseURL: String
    /// True when the current provider has explicit consent to receive job/resume data.
    public let consentGranted: Bool
    public let preferredLocations: String
    public let locationFilterEnabled: Bool
    public let locationAllowRemote: Bool
    public let locationAllowHybrid: Bool
    public let locationAllowOnsite: Bool

    public init(
        llmModel: String,
        llmProvider: String = "lmstudio",
        llmBaseURL: String = "http://127.0.0.1:1234",
        consentGranted: Bool = true,
        preferredLocations: String,
        locationFilterEnabled: Bool,
        locationAllowRemote: Bool,
        locationAllowHybrid: Bool,
        locationAllowOnsite: Bool
    ) {
        self.llmModel = llmModel
        self.llmProvider = llmProvider
        self.llmBaseURL = llmBaseURL
        self.consentGranted = consentGranted
        self.preferredLocations = preferredLocations
        self.locationFilterEnabled = locationFilterEnabled
        self.locationAllowRemote = locationAllowRemote
        self.locationAllowHybrid = locationAllowHybrid
        self.locationAllowOnsite = locationAllowOnsite
    }
}
