import JobhuntCore
import SwiftUI

public enum SidebarSection: String, CaseIterable, Hashable {
    case dashboard
    case jobs
    case resumes
    case dataQuality
    case needsAction
    case llmQueue
    case sites
    case duplicates
    case applicationHistory
}

/// Typed selection value for the sidebar List. Maps to router state.
public enum SidebarItem: Hashable, Sendable {
    case dashboard
    case needsAction
    case jobsAll
    case jobs(JobStatus)
    case resumes
    case sites
    case duplicates
    case llmQueue
    case dataQuality
    case applicationHistory
    case savedSearch(String)

    /// Stable, persistable token for the last-viewed view (round-trips via `init?(persistedID:)`).
    /// Used to restore the sidebar selection on relaunch.
    var persistedID: String {
        switch self {
        case .dashboard: return "dashboard"
        case .needsAction: return "needsAction"
        case .jobsAll: return "jobsAll"
        case let .jobs(status): return "jobs:\(status.rawValue)"
        case .resumes: return "resumes"
        case .sites: return "sites"
        case .duplicates: return "duplicates"
        case .llmQueue: return "llmQueue"
        case .dataQuality: return "dataQuality"
        case .applicationHistory: return "applicationHistory"
        case let .savedSearch(id): return "savedSearch:\(id)"
        }
    }

    /// Reconstruct a selection from its `persistedID`. Returns nil for an empty/unknown token.
    init?(persistedID raw: String) {
        switch raw {
        case "dashboard": self = .dashboard
        case "needsAction": self = .needsAction
        case "jobsAll": self = .jobsAll
        case "resumes": self = .resumes
        case "sites": self = .sites
        case "duplicates": self = .duplicates
        case "llmQueue": self = .llmQueue
        case "dataQuality": self = .dataQuality
        case "applicationHistory": self = .applicationHistory
        default:
            if raw.hasPrefix("jobs:"), let status = JobStatus(rawValue: String(raw.dropFirst("jobs:".count))) {
                self = .jobs(status)
            } else if raw.hasPrefix("savedSearch:") {
                self = .savedSearch(String(raw.dropFirst("savedSearch:".count)))
            } else {
                return nil
            }
        }
    }
}

/// Tabs in the ⌘, Settings window (rawValue matches each tab's `.tag`).
public enum SettingsPane: Int {
    case general = 0
    case jobs = 1
    case llm = 2
    case data = 3
    case debug = 4
    /// 5, not 4, so Debug keeps its raw value — the selected pane is persisted, and renumbering
    /// would land a returning user on a different tab than the one they left.
    case search = 5
}

/// An app-wide queue attention banner (TASK-542). `showsAISettings` adds a one-click jump to the
/// AI Provider settings tab — used for credential failures.
public struct QueueAlert: Equatable {
    public let message: String
    public let showsAISettings: Bool
}

@Observable
public final class Router {
    public var selectedSection: SidebarSection = .jobs
    public var selectedJobID: String?
    public var selectedSiteID: String?
    /// Smart-folder status filter set by sidebar item clicks (nil = All Jobs)
    public var sidebarJobFilter: JobStatus?
    public var statusFilter: String? // legacy; kept for non-sidebar callers
    public var searchText: String = ""
    public var activeSavedSearchID: String?
    /// Triggers AddJobSheet from app menu / ⌘N
    public var showAddJobSheet: Bool = false
    /// Triggers search field focus from app menu / ⌘K
    public var focusSearch: Bool = false
    /// Triggers CSV export of the current filtered Jobs view from app menu / ⌘⇧E
    public var exportJobsRequested: Bool = false
    /// One-shot: set by the Dashboard "needs a referral" card to open Jobs pre-filtered to
    /// referral-needs-outreach. JobsView consumes it (enables the filter) and clears it (TASK-644).
    public var focusReferralOutreach: Bool = false
    /// Which tab the ⌘, Settings window should show. Set by deep-links (e.g. the
    /// "AI not configured" nudge) before opening the window.
    public var settingsTab: SettingsPane = .general
    /// Session-scoped dismissal of the first-run setup checklist (TASK-498). In-memory by design:
    /// the checklist returns on next launch if setup is still incomplete ("persistent until
    /// configured"), but the user can hide it for the current session.
    public var setupChecklistDismissed: Bool = false
    /// One-shot: the Jobs list scrolls to this job id when it's opened via *external* navigation
    /// (LLM Queue "Open Job", notification deep-links). Cleared once the list scrolls. User clicks
    /// select through the list binding and don't set this, so an in-list click never re-scrolls.
    public var pendingJobScrollID: String?
    /// App-wide attention banner for a queue problem the user must act on (e.g. a rejected API key).
    /// Set by PlatformIntegration so the banner is visible from *any* screen, not just the LLM Queue
    /// (TASK-542). Cleared on dismiss or when the queue next succeeds.
    public var queueAlert: QueueAlert?
    /// Set by "Add Note" affordances (e.g. the Jobs row context menu) to ask the job detail view
    /// to open the selected job's Timeline tab for note entry. Cleared once consumed.
    public var composeNoteJobID: String?
    /// Presents the Keyboard Shortcuts overlay (TASK-499) — set by the bare-`?` key monitor and the
    /// Help ▸ Keyboard Shortcuts menu item; cleared when the overlay is dismissed.
    public var showKeyboardShortcuts: Bool = false
    /// Installed by the visible job-detail view so the ⌃Tab / ⌃⇧Tab key monitor can cycle its tabs
    /// (`forward` = ⌃Tab, `!forward` = ⌃⇧Tab). Nil when no detail is on screen, in which case the
    /// monitor lets the key event pass through untouched (TASK-499). The `token` lets the outgoing
    /// detail avoid clearing a hook the incoming detail already installed during a per-job re-mount.
    public struct DetailTabCycler {
        public let token: UUID
        public let cycle: (_ forward: Bool) -> Void
    }

    public var detailTabCycler: DetailTabCycler?

    public init() {}

    /// Select a job by its `Job.id` and switch to the Jobs section.
    /// Callers that only have a public job number must resolve it to an id first
    /// (the Router has no model access).
    ///
    /// When `jobStatus` is supplied and the active sidebar smart-folder filter would *hide* that job
    /// (a non-nil filter set to a different status), the filter is switched to the job's status so the
    /// externally-targeted job is actually visible. Without this, selecting a job outside the current
    /// filter silently lands on an unchanged, empty-looking list — e.g. capturing a `new` job and
    /// "Open in app" while the Jobs sidebar is on `Interested` (TASK-596). An `All` view (nil filter)
    /// or a filter already matching the job is left untouched, so a normal in-context open never
    /// narrows the view.
    public func selectJob(id: String, jobStatus: JobStatus? = nil) {
        selectedSection = .jobs
        if let jobStatus, let filter = sidebarJobFilter, filter != jobStatus {
            sidebarJobFilter = jobStatus
        }
        selectedJobID = id
        pendingJobScrollID = id
    }

    public func navigateToSection(_ section: SidebarSection) {
        selectedSection = section
    }
}
