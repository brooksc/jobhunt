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
    public static let llmAPIKeyDeepSeek = "llm_api_key_deepseek"
    public static let llmModel = "llm_model"
    public static let llmTimeout = "llm_timeout"
    public static let siteReviewIntervalDays = "site_review_interval_days"
    public static let followupDefaultDays = "followup_default_days"
    public static let jobDescriptionMarkdown = "job_description_markdown"
    public static let preferredLocations = "preferred_locations"
    public static let preferredMetros = "preferred_metros"
    public static let locationFilterEnabled = "location_filter_enabled"
    public static let locationAllowRemote = "location_allow_remote"
    /// Where the user is eligible to work *remotely*, kept separate from `preferredLocations`.
    ///
    /// Those two answer different questions. Preferred locations is "where would I commute to",
    /// which is about onsite/hybrid; remote eligibility is "which country's remote postings can I
    /// legally take". Conflating them meant a user whose preferred location is "Seattle, WA" had no
    /// way to say "remote anywhere in the US" without also implying they'd only commute to the US,
    /// and a non-US user had no way to say anything at all — eligibility fell back to a hardcoded
    /// list of US tokens. Empty means "use preferred locations, then the US fallback", i.e. exactly
    /// the previous behaviour.
    public static let remoteEligibilityRegions = "remote_eligibility_regions"
    public static let locationAllowHybrid = "location_allow_hybrid"
    public static let locationAllowOnsite = "location_allow_onsite"
    /// Minimum acceptable salary. 0 disables the check. Compared against the TOP of a job's range.
    public static let minSalary = "min_salary"
    /// Minimum acceptable fit score (0–100). 0 disables the check.
    public static let minFitScore = "min_fit_score"
    /// JSON array of `ScoringFeedback`. Stored as a setting rather than a SwiftData model so no
    /// schema migration is needed for what is a short, user-curated list.
    public static let scoringFeedback = "scoring_feedback"
    public static let llmQueuePaused = "llm_queue_paused"
    /// Why the queue is paused (`QueuePauseReason`). Persisted separately from the boolean because a
    /// user pause and an auto-pause need different words and different urgency (TASK-524).
    public static let llmQueuePauseReason = "llm_queue_pause_reason"
    /// Hide the Debug settings tab. Default false (shown). Re-enable from General settings.
    public static let hideDebugTab = "hide_debug_tab"
    public static let llmOpenRouterFreeRotate = "llm_openrouter_free_rotate"
    public static let availabilityAutoCheckEnabled = "availability_auto_check_enabled"
    public static let availabilityAutoCheckIntervalDays = "availability_auto_check_interval_days"
    public static let availabilityStaleDays = "availability_stale_days"
    /// Rotation cursor for LinkedIn availability checks. LinkedIn is capped per run, so this advances
    /// each run to guarantee every posting is eventually checked instead of relying on random sampling.
    public static let linkedInRotationOffset = "linkedin_rotation_offset"
    public static let availabilityLastAutoCheckAt = "availability_last_auto_check_at"
    /// ISO-8601 timestamp of the last "jobs may be gone" macOS notification, used to rate-limit it to
    /// at most once per 24h so a long foreground session can't spam the user.
    public static let availabilityLastNotifiedAt = "availability_last_notified_at"
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
    /// Persisted last-selected job-detail tab (DetailTab rawValue), so opening a job restores the tab
    /// you last deliberately chose (e.g. "Fit") instead of always resetting to Overview.
    public static let detailLastTab = "detail_last_tab"
    /// Set once the user has acknowledged that opening a job AI prompt in an external chat embeds the
    /// resume + job description in a URL (TASK-606). Gates the first external-open only.
    public static let aiPromptExternalOpenAcknowledged = "ai_prompt_external_open_acknowledged"
    /// Free-text personal/application details (name, contact, work authorization, EEO answers, …) the
    /// user provides so the Codex auto-apply prompt can fill application fields (TASK-606). Stored
    /// locally in the SwiftData store; never sent anywhere by the app itself.
    public static let applicationPersonalInfo = "application_personal_info"
    /// Set once the user has acknowledged that the Codex auto-apply prompt embeds their Application
    /// Details (address, EEO answers, …) when copied (TASK-606). Gates the first such copy only.
    public static let autoApplyPersonalInfoAcknowledged = "auto_apply_personal_info_acknowledged"

    /// API key settings that must live in Keychain, not SwiftData (App Store hygiene).
    public static let keychainKeys: Set<String> = [
        llmAPIKey, llmAPIKeyOpenAI, llmAPIKeyAnthropic,
        llmAPIKeyGoogle, llmAPIKeyOpenRouter, llmAPIKeyCustom, llmAPIKeyDeepSeek
    ]
}
