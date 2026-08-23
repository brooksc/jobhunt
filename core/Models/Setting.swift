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
    /// User-authored prompt templates as a JSON array (TASK-627). Stored as a setting rather than a
    /// model: no migration, and the whole list round-trips as one value.
    public static let customPromptTemplates = "custom_prompt_templates"
    /// End-of-day recap reminder (TASK-623 #11). Off by default — an unasked-for daily nudge about
    /// job hunting is exactly the kind of pressure this feature is meant not to apply.
    public static let dailyRecapReminderEnabled = "daily_recap_reminder_enabled"
    /// Hour of the local day (0–23) the reminder fires.
    public static let dailyRecapReminderHour = "daily_recap_reminder_hour"
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
    /// Whether jobs are published to the system Spotlight index (TASK-590). On by default, matching
    /// the behaviour when indexing was unconditional, but a job search is private enough that
    /// "titles and companies appear in system-wide search" has to be refusable — and without this,
    /// Clear Spotlight Index only held until the next launch rebuilt it.
    public static let spotlightIndexingEnabled = "spotlight_indexing_enabled"
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

    // MARK: - Automatic search (TASK-692)

    /// The master switch. Off by default: nothing sweeps until the user has seen and edited what it
    /// will do.
    public static let discoveryEnabled = "discovery_enabled"

    /// Gate-A criteria, stored under their *own* keys rather than reusing `preferredLocations` and
    /// friends.
    ///
    /// Those keys feed `JobRequirements`, which badges every job in the app. Aliasing would mean
    /// that widening the search — a change made on a screen about *where to look* — silently
    /// re-evaluated hundreds of existing jobs. So the discovery criteria are *seeded* from them on
    /// first use and owned separately after that.
    ///
    /// All comma-separated, matching how `preferredLocations` already stores a list.
    public static let discoveryTitleInclude = "discovery_title_include"
    public static let discoveryTitleExclude = "discovery_title_exclude"
    public static let discoveryLocationAllow = "discovery_location_allow"
    public static let discoveryLocationAlwaysAllow = "discovery_location_always_allow"
    public static let discoveryLocationBlock = "discovery_location_block"
    public static let discoveryLocationBlockHard = "discovery_location_block_hard"
    public static let discoveryMinSalary = "discovery_min_salary"
    public static let discoveryMaxAgeDays = "discovery_max_age_days"

    /// Set once the criteria have been seeded from the existing requirement settings, so a user who
    /// deliberately empties a list doesn't get it refilled on the next launch.
    public static let discoveryCriteriaSeeded = "discovery_criteria_seeded"

    /// Ingest ceilings. A circuit breaker against a misconfiguration, not a working budget — see
    /// `DiscoveryCaps`.
    public static let discoveryMaxIngestsPerSweep = "discovery_max_ingests_per_sweep"
    public static let discoveryMaxIngestsPerDay = "discovery_max_ingests_per_day"
    /// The rolling day counter behind `discoveryMaxIngestsPerDay`.
    public static let discoveryIngestsToday = "discovery_ingests_today"
    public static let discoveryIngestsTodayDate = "discovery_ingests_today_date"

    /// API key settings that must live in Keychain, not SwiftData (App Store hygiene).
    public static let keychainKeys: Set<String> = [
        llmAPIKey, llmAPIKeyOpenAI, llmAPIKeyAnthropic,
        llmAPIKeyGoogle, llmAPIKeyOpenRouter, llmAPIKeyCustom, llmAPIKeyDeepSeek
    ]
}
