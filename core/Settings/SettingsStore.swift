import Foundation
import Observation
import Security
import SwiftData

/// Whether a provider's API key is present, absent, or unreadable due to a Keychain failure (TASK-569).
public enum APIKeyAvailability: Equatable, Sendable {
    case present
    case missing
    case unavailable(OSStatus)
}

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
    // Both default to 0 (off) — a requirement is only applied once the user sets their own number.
    SettingsKey.minSalary: "0",
    SettingsKey.minFitScore: "0",
    SettingsKey.scoringFeedback: "[]",
    SettingsKey.customPromptTemplates: "[]",
    SettingsKey.dailyRecapReminderEnabled: "false",
    SettingsKey.dailyRecapReminderHour: "18",
    SettingsKey.spotlightIndexingEnabled: "true",
    SettingsKey.llmQueuePaused: "false",
    SettingsKey.llmQueuePauseReason: QueuePauseReason.user.rawValue,
    SettingsKey.llmOpenRouterFreeRotate: "false",
    // Off until the user has seen and edited what a sweep would do (TASK-692).
    SettingsKey.discoveryEnabled: "false",
    SettingsKey.discoveryTitleInclude: "",
    SettingsKey.discoveryTitleExclude: "Intern, Junior, Graduate, Apprentice",
    SettingsKey.discoveryLocationAllow: "",
    SettingsKey.discoveryLocationAlwaysAllow: "",
    SettingsKey.discoveryLocationBlock: "",
    SettingsKey.discoveryLocationBlockHard: "",
    SettingsKey.discoveryMinSalary: "0",
    SettingsKey.discoveryMaxAgeDays: "0",
    SettingsKey.discoveryCriteriaSeeded: "false",
    SettingsKey.discoveryMaxIngestsPerSweep: "50",
    SettingsKey.discoveryMaxIngestsPerDay: "200",
    SettingsKey.discoveryIngestsToday: "0",
    SettingsKey.discoveryIngestsTodayDate: "",
    SettingsKey.availabilityAutoCheckEnabled: "true",
    SettingsKey.availabilityAutoCheckIntervalDays: "1",
    SettingsKey.availabilityStaleDays: "21",
    SettingsKey.availabilityLastAutoCheckAt: "",
    SettingsKey.availabilityLastNotifiedAt: "",
    SettingsKey.llmPriceInput: "0",
    SettingsKey.llmPriceOutput: "0",
    SettingsKey.llmConsentAnthropic: "0",
    SettingsKey.llmConsentGoogle: "0",
    SettingsKey.llmConsentOpenRouter: "0",
    SettingsKey.llmConsentOpenAI: "0",
    SettingsKey.lastSidebarSelection: "",
    SettingsKey.jobsSortKey: "capturedAt",
    SettingsKey.jobsSortAscending: "false",
    SettingsKey.detailLastTab: ""
]

@Observable
public final class SettingsStore {
    private var modelContext: ModelContext
    private var keychain: any KeychainAccess
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

    public init(modelContext: ModelContext, keychain: any KeychainAccess = KeychainStore()) {
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
            setLocal("lmstudio", forKey: SettingsKey.llmProvider)
        }
    }

    // MARK: - Generic accessors

    public func string(forKey key: String) -> String {
        if SettingsKey.keychainKeys.contains(key) {
            return keychain.get(key) ?? ""
        }
        return cache[key] ?? settingsDefaults[key] ?? ""
    }

    /// Write a setting.
    ///
    /// Throws only for the six keychain-backed API-key keys, whose write can genuinely fail (locked
    /// keychain, denied ACL). It used to catch that, set `keychainWriteError` and return normally, so
    /// a programmatic caller — a restore or a key rotation — was told the write succeeded when the
    /// key had not been stored. `keychainWriteError` is still set for the UI to observe; the throw is
    /// additional, not a replacement.
    public func set(_ value: String, forKey key: String) throws {
        guard SettingsKey.keychainKeys.contains(key) else {
            setLocal(value, forKey: key)
            return
        }
        do {
            try keychain.set(value, forKey: key)
            keychainWriteError = nil
        } catch {
            keychainWriteError = error.localizedDescription
            throw error
        }
    }

    /// The non-keychain write, which cannot fail.
    ///
    /// Exists because SwiftUI property setters can't throw: the typed shortcut properties below would
    /// otherwise need `try?`, which would put silent failure back exactly where it was removed. Every
    /// one of them writes a non-keychain key, so routing them here is safe rather than a loophole —
    /// the assert holds that line if a future key changes category.
    private func setLocal(_ value: String, forKey key: String) {
        assert(
            !SettingsKey.keychainKeys.contains(key),
            "\(key) is keychain-backed — use the throwing set(_:forKey:) so a failed write is visible"
        )
        cache[key] = value
        persistToStore(key: key, value: value)
    }

    public func bool(forKey key: String) -> Bool {
        let strVal = string(forKey: key)
        return strVal == "true" || strVal == "1"
    }

    public func setBool(_ value: Bool, forKey key: String) {
        setLocal(value ? "true" : "false", forKey: key)
    }

    public func int(forKey key: String) -> Int {
        Int(string(forKey: key)) ?? 0
    }

    public func setInt(_ value: Int, forKey key: String) {
        setLocal(String(value), forKey: key)
    }

    public func double(forKey key: String) -> Double {
        Double(string(forKey: key)) ?? 0
    }

    public func setDouble(_ value: Double, forKey key: String) {
        setLocal(String(value), forKey: key)
    }

    // MARK: - Typed shortcut properties (most-used settings)

    public var llmProvider: String {
        get { string(forKey: SettingsKey.llmProvider) }
        set { setLocal(newValue, forKey: SettingsKey.llmProvider) }
    }

    public var llmBaseURL: String {
        get { string(forKey: SettingsKey.llmBaseURL) }
        set { setLocal(newValue, forKey: SettingsKey.llmBaseURL) }
    }

    public var llmModel: String {
        get { string(forKey: SettingsKey.llmModel) }
        set { setLocal(newValue, forKey: SettingsKey.llmModel) }
    }

    public var llmTimeout: Int {
        get { int(forKey: SettingsKey.llmTimeout) }
        set { setInt(newValue, forKey: SettingsKey.llmTimeout) }
    }

    public var llmQueuePaused: Bool {
        get { bool(forKey: SettingsKey.llmQueuePaused) }
        set { setBool(newValue, forKey: SettingsKey.llmQueuePaused) }
    }

    /// TASK-623 #11: opt-in only. A daily nudge nobody asked for is the pressure this feature is
    /// specifically meant not to apply, so the default is off and dismissing it costs nothing.
    public var dailyRecapReminderEnabled: Bool {
        get { bool(forKey: SettingsKey.dailyRecapReminderEnabled) }
        set { setBool(newValue, forKey: SettingsKey.dailyRecapReminderEnabled) }
    }

    /// Hour of the local day the reminder fires, clamped to 0–23 so a bad stored value can't make
    /// the scheduler compute a date in the past forever.
    public var dailyRecapReminderHour: Int {
        get { min(max(int(forKey: SettingsKey.dailyRecapReminderHour), 0), 23) }
        set { setInt(min(max(newValue, 0), 23), forKey: SettingsKey.dailyRecapReminderHour) }
    }

    /// Whether jobs are published to Spotlight (TASK-590). Defaults on — that was the behaviour when
    /// indexing was unconditional — but turning it off must actually stick, which is why the launch
    /// pass reads this rather than always running.
    public var spotlightIndexingEnabled: Bool {
        get { bool(forKey: SettingsKey.spotlightIndexingEnabled) }
        set { setBool(newValue, forKey: SettingsKey.spotlightIndexingEnabled) }
    }

    /// User-authored prompt templates (TASK-627), ordered for the menu.
    ///
    /// A decode failure yields an empty list rather than throwing: a corrupt value would otherwise
    /// make Settings unopenable, and the templates are re-creatable. The write is the recovery.
    public var customPromptTemplates: [PromptTemplate] {
        get {
            let json = string(forKey: SettingsKey.customPromptTemplates)
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([PromptTemplate].self, from: data)
            else { return [] }
            return decoded.sorted { $0.sortOrder < $1.sortOrder }
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            setLocal(json, forKey: SettingsKey.customPromptTemplates)
        }
    }

    /// Only the enabled ones, in order — what the Prompt AI menu shows.
    public var enabledPromptTemplates: [PromptTemplate] {
        customPromptTemplates.filter(\.isEnabled)
    }

    public func upsertPromptTemplate(_ template: PromptTemplate) {
        var templates = customPromptTemplates
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            var appended = template
            // Append rather than insert: a new prompt belongs at the end of the user's own order.
            appended.sortOrder = (templates.map(\.sortOrder).max() ?? -1) + 1
            templates.append(appended)
        }
        customPromptTemplates = templates
    }

    public func removePromptTemplate(id: String) {
        customPromptTemplates = customPromptTemplates.filter { $0.id != id }
    }

    /// Moves a template one place up or down, renumbering so the order is always dense.
    public func movePromptTemplate(id: String, up: Bool) {
        var templates = customPromptTemplates
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard templates.indices.contains(target) else { return }
        templates.swapAt(index, target)
        for (position, var template) in templates.enumerated() {
            template.sortOrder = position
            templates[position] = template
        }
        customPromptTemplates = templates
    }

    /// Why the queue is paused. Unrecognised values read back as `.user` — the conservative default,
    /// since claiming an automatic failure that didn't happen would send the user looking for a
    /// provider problem that isn't there.
    public var llmQueuePauseReason: QueuePauseReason {
        get { QueuePauseReason(rawValue: string(forKey: SettingsKey.llmQueuePauseReason)) ?? .user }
        set { setLocal(newValue.rawValue, forKey: SettingsKey.llmQueuePauseReason) }
    }

    /// Pauses (or resumes) with the reason recorded in one step, so the two can't drift apart.
    /// Resuming resets the reason to `.user`: a stale "auto-paused after failures" surviving a
    /// successful resume would mislabel the next deliberate pause.
    public func setQueuePaused(_ paused: Bool, reason: QueuePauseReason = .user) {
        llmQueuePaused = paused
        llmQueuePauseReason = paused ? reason : .user
    }

    /// The last-viewed sidebar selection, persisted so relaunch restores the same view. Opaque
    /// token serialized by `SidebarItem.persistedID`; "" means none stored yet (default view).
    public var lastSidebarSelection: String {
        get { string(forKey: SettingsKey.lastSidebarSelection) }
        set { setLocal(newValue, forKey: SettingsKey.lastSidebarSelection) }
    }

    /// Persisted Jobs-list sort (review-2 #7). Survives sidebar-selection resets and relaunch.
    /// Stored as the `JobsSortKey` rawValue; the view maps it back to the enum.
    public var jobsSortKey: String {
        get { string(forKey: SettingsKey.jobsSortKey) }
        set { setLocal(newValue, forKey: SettingsKey.jobsSortKey) }
    }

    public var jobsSortAscending: Bool {
        get { bool(forKey: SettingsKey.jobsSortAscending) }
        set { setBool(newValue, forKey: SettingsKey.jobsSortAscending) }
    }

    /// Persisted last deliberately-selected job-detail tab (a `DetailTab` rawValue). Empty until the
    /// user picks a tab; the detail view maps it back to the enum with an Overview fallback.
    public var detailLastTab: String {
        get { string(forKey: SettingsKey.detailLastTab) }
        set { setLocal(newValue, forKey: SettingsKey.detailLastTab) }
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
        set { setLocal(newValue, forKey: SettingsKey.preferredLocations) }
    }

    /// Where the user may work remotely — see `SettingsKey.remoteEligibilityRegions`. Empty keeps the
    /// previous behaviour.
    public var remoteEligibilityRegions: String {
        get { string(forKey: SettingsKey.remoteEligibilityRegions) }
        set { setLocal(newValue, forKey: SettingsKey.remoteEligibilityRegions) }
    }

    /// Minimum acceptable salary; 0 means no salary requirement. Compared against the top of a
    /// job's range, so a posting is only rejected when even its ceiling falls short.
    public var minSalary: Int {
        get { int(forKey: SettingsKey.minSalary) }
        set { setInt(max(0, newValue), forKey: SettingsKey.minSalary) }
    }

    /// Minimum acceptable fit score (0–100); 0 means no fit requirement.
    public var minFitScore: Int {
        get { int(forKey: SettingsKey.minFitScore) }
        set { setInt(min(100, max(0, newValue)), forKey: SettingsKey.minFitScore) }
    }

    /// Corrections the user made to requirement assessments. Applied deterministically when gaps
    /// are built, so adding one fixes every stored score on the next recompute at no LLM cost.
    public var scoringFeedback: [ScoringFeedback] {
        get {
            guard let data = string(forKey: SettingsKey.scoringFeedback).data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ScoringFeedback].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            setLocal(json, forKey: SettingsKey.scoringFeedback)
        }
    }

    public func addScoringFeedback(_ entry: ScoringFeedback) {
        scoringFeedback += [entry]
    }

    public func removeScoringFeedback(id: String) {
        scoringFeedback = scoringFeedback.filter { $0.id != id }
    }

    /// Replaces a correction in place, keeping its position in the list.
    ///
    /// Position matters more than it looks: `verdict(forRequirement:jobNumber:)` short-circuits on
    /// the first `neverCredit` it finds, so reordering the array on every edit would be a silent
    /// change to which rule wins when two match.
    public func updateScoringFeedback(_ updated: ScoringFeedback) {
        guard let index = scoringFeedback.firstIndex(where: { $0.id == updated.id }) else { return }
        var entries = scoringFeedback
        entries[index] = updated
        scoringFeedback = entries
    }

    public var preferredMetros: String {
        get { string(forKey: SettingsKey.preferredMetros) }
        set { setLocal(newValue, forKey: SettingsKey.preferredMetros) }
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
        setLocal(model, forKey: "llm_model_\(provider)")
        llmModel = model
    }

    // MARK: - Keychain API key accessors

    public func apiKey(forProvider provider: String) -> String {
        let key = keychainKey(forProvider: provider)
        return keychain.get(key) ?? ""
    }

    /// Whether a provider's API key is present, genuinely absent, or unreadable due to a Keychain
    /// error (locked keychain, ACL denial, corrupted item, …). Lets diagnostics/UI distinguish "no key
    /// set" from "key exists but the Keychain wouldn't return it" instead of collapsing both to empty
    /// (TASK-569). Pure — reads the Keychain but mutates no observable state, so it's safe to call
    /// off the render path (call it on appear/refresh, not in a SwiftUI `body`).
    public func apiKeyAvailability(forProvider provider: String) -> APIKeyAvailability {
        let key = keychainKey(forProvider: provider)
        do {
            guard let value = try keychain.read(key),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .missing }
            return .present
        } catch let KeychainError.readFailed(status) {
            return .unavailable(status)
        } catch {
            return .unavailable(errSecInternalError)
        }
    }

    private func keychainKey(forProvider provider: String) -> String {
        provider == "default" ? SettingsKey.llmAPIKey : "llm_api_key_\(provider)"
    }

    /// Throws for the same reason `set` does — this is the path the API-key field actually uses, and
    /// it swallowed failures identically.
    public func setAPIKey(_ value: String, forProvider provider: String) throws {
        let key = keychainKey(forProvider: provider)
        // Trim pasted whitespace/newlines — a trailing space alone makes a valid key get rejected
        // (e.g. Google returns 401) with no obvious cause.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try keychain.set(trimmed, forKey: key)
            keychainWriteError = nil
        } catch {
            keychainWriteError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Private

    /// Test-only fault injection (TASK-479): when set, `loadCache`/`reload` treat the load as failed
    /// (SwiftData's fetch can't be made to error on demand). Nil in production.
    public var loadFault: Error?

    private func loadCache() {
        do {
            if let loadFault {
                throw loadFault
            }
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
            loadError = "Couldn't load saved settings (\(type(of: error))). " +
                "Your preferences weren't read; relaunch to retry."
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
        let combined = combinedPreferredLocations(locations: preferredLocations, metros: preferredMetros)
        return ExtractionSettings(
            llmModel: llmModel,
            llmTimeout: llmTimeout,
            llmProvider: provider,
            llmBaseURL: baseURL,
            consentGranted: consentGranted,
            preferredLocations: combined,
            remoteEligibilityRegions: remoteEligibilityRegions,
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
    /// Per-request timeout in seconds, as configured by the user. The queue derives its hard
    /// wall-clock deadline from this (TASK-657) rather than introducing a second setting.
    public let llmTimeout: Int
    public let llmProvider: String
    public let llmBaseURL: String
    /// True when the current provider has explicit consent to receive job/resume data.
    public let consentGranted: Bool
    public let preferredLocations: String
    /// Where the user may work remotely; empty falls back to `preferredLocations`.
    public let remoteEligibilityRegions: String
    public let locationFilterEnabled: Bool
    public let locationAllowRemote: Bool
    public let locationAllowHybrid: Bool
    public let locationAllowOnsite: Bool

    public init(
        llmModel: String,
        llmTimeout: Int = 300,
        llmProvider: String = "lmstudio",
        llmBaseURL: String = "http://127.0.0.1:1234",
        consentGranted: Bool = true,
        preferredLocations: String,
        remoteEligibilityRegions: String = "",
        locationFilterEnabled: Bool,
        locationAllowRemote: Bool,
        locationAllowHybrid: Bool,
        locationAllowOnsite: Bool
    ) {
        self.llmModel = llmModel
        self.llmTimeout = llmTimeout
        self.llmProvider = llmProvider
        self.llmBaseURL = llmBaseURL
        self.consentGranted = consentGranted
        self.preferredLocations = preferredLocations
        self.remoteEligibilityRegions = remoteEligibilityRegions
        self.locationFilterEnabled = locationFilterEnabled
        self.locationAllowRemote = locationAllowRemote
        self.locationAllowHybrid = locationAllowHybrid
        self.locationAllowOnsite = locationAllowOnsite
    }
}
