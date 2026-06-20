import Foundation
import SwiftData

@Model
public final class Setting {
    @Attribute(.unique) public var key: String
    public var value: String
    public var updatedAt: Date

    public init(key: String, value: String, updatedAt: Date = Date()) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

/// Mirrors SETTINGS_DEFAULTS from server/db.js — keys only; defaults are in SettingsStore (task-035).
public enum SettingsKey {
    public static let llmProvider = "llm_provider"
    public static let llmBaseURL = "llm_base_url"
    public static let llmAPIKey = "llm_api_key"
    public static let llmAPIKeyOpenAI = "llm_api_key_openai"
    public static let llmAPIKeyAnthropic = "llm_api_key_anthropic"
    public static let llmAPIKeyGoogle = "llm_api_key_google"
    public static let llmAPIKeyOpenRouter = "llm_api_key_openrouter"
    public static let llmAPIKeyCustom = "llm_api_key_custom"
    public static let llmModel = "llm_model"
    public static let llmTimeout = "llm_timeout"
    public static let siteReviewIntervalDays = "site_review_interval_days"
    public static let followupDefaultDays = "followup_default_days"
    public static let jobDescriptionMarkdown = "job_description_markdown"
    public static let preferredLocations = "preferred_locations"
    public static let preferredMetros = "preferred_metros"
    public static let locationFilterEnabled = "location_filter_enabled"
    public static let locationAllowRemote = "location_allow_remote"
    public static let locationAllowHybrid = "location_allow_hybrid"
    public static let locationAllowOnsite = "location_allow_onsite"
    public static let llmQueuePaused = "llm_queue_paused"
    /// Hide the Debug settings tab. Default false (shown). Re-enable from General settings.
    public static let hideDebugTab = "hide_debug_tab"
    public static let llmOpenRouterFreeRotate = "llm_openrouter_free_rotate"
    public static let availabilityAutoCheckEnabled = "availability_auto_check_enabled"
    public static let availabilityAutoCheckIntervalDays = "availability_auto_check_interval_days"
    public static let availabilityStaleDays = "availability_stale_days"
    public static let availabilityLastAutoCheckAt = "availability_last_auto_check_at"
    public static let llmPriceInput = "llm_price_input"
    public static let llmPriceOutput = "llm_price_output"
    public static let llmConsentAnthropic = "llm_consent_anthropic"
    public static let llmConsentGoogle = "llm_consent_google"
    public static let llmConsentOpenRouter = "llm_consent_openrouter"
    public static let llmConsentOpenAI = "llm_consent_openai"
    /// Persisted last-viewed sidebar selection, so relaunch restores the same view (e.g. "Pursuing").
    public static let lastSidebarSelection = "last_sidebar_selection"
    /// Persisted Jobs-list sort, so it survives sidebar-selection changes and relaunch.
    public static let jobsSortKey = "jobs_sort_key"
    public static let jobsSortAscending = "jobs_sort_ascending"

    /// API key settings that must live in Keychain, not SwiftData (App Store hygiene).
    public static let keychainKeys: Set<String> = [
        llmAPIKey, llmAPIKeyOpenAI, llmAPIKeyAnthropic,
        llmAPIKeyGoogle, llmAPIKeyOpenRouter, llmAPIKeyCustom
    ]
}
