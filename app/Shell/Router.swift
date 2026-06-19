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
    case help

    var title: String {
        switch self {
        case .dashboard:   "Dashboard"
        case .jobs:        "Jobs"
        case .resumes:     "Resumes"
        case .dataQuality: "Data Quality"
        case .needsAction: "Needs Action"
        case .llmQueue:    "LLM Queue"
        case .sites:       "Sites"
        case .duplicates:  "Duplicates"
        case .help:        "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:   "chart.bar"
        case .jobs:        "briefcase"
        case .resumes:     "doc.text"
        case .dataQuality: "checkmark.shield"
        case .needsAction: "bell"
        case .llmQueue:    "cpu"
        case .sites:       "globe"
        case .duplicates:  "doc.on.doc"
        case .help:        "questionmark.circle"
        }
    }
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
    case help
    case savedSearch(String)

    /// The display label shown in the sidebar row (matches NSTextField text for AppKit selection).
    var sidebarLabel: String? {
        switch self {
        case .dashboard:         return "Dashboard"
        case .needsAction:       return "Needs Action"
        case .jobsAll:           return "All Jobs"
        case .jobs(let status):  return status.displayName
        case .resumes:           return "Resumes"
        case .sites:             return "Sites"
        case .duplicates:        return "Duplicates"
        case .llmQueue:          return "LLM Queue"
        case .dataQuality:       return "Data Quality"
        case .help:              return "Help"
        case .savedSearch:       return nil  // dynamic name — caller handles
        }
    }

    /// Stable, persistable token for the last-viewed view (round-trips via `init?(persistedID:)`).
    /// Used to restore the sidebar selection on relaunch.
    var persistedID: String {
        switch self {
        case .dashboard:           return "dashboard"
        case .needsAction:         return "needsAction"
        case .jobsAll:             return "jobsAll"
        case .jobs(let status):    return "jobs:\(status.rawValue)"
        case .resumes:             return "resumes"
        case .sites:               return "sites"
        case .duplicates:          return "duplicates"
        case .llmQueue:            return "llmQueue"
        case .dataQuality:         return "dataQuality"
        case .help:                return "help"
        case .savedSearch(let id): return "savedSearch:\(id)"
        }
    }

    /// Reconstruct a selection from its `persistedID`. Returns nil for an empty/unknown token.
    init?(persistedID raw: String) {
        switch raw {
        case "dashboard":   self = .dashboard
        case "needsAction": self = .needsAction
        case "jobsAll":     self = .jobsAll
        case "resumes":     self = .resumes
        case "sites":       self = .sites
        case "duplicates":  self = .duplicates
        case "llmQueue":    self = .llmQueue
        case "dataQuality": self = .dataQuality
        case "help":        self = .help
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
}

@Observable
public final class Router {
    public var selectedSection: SidebarSection = .jobs
    public var selectedJobID: String?
    public var selectedSiteID: String?
    /// Smart-folder status filter set by sidebar item clicks (nil = All Jobs)
    public var sidebarJobFilter: JobStatus?
    public var statusFilter: String?  // legacy; kept for non-sidebar callers
    public var searchText: String = ""
    public var activeSavedSearchID: String?
    /// Triggers AddJobSheet from app menu / ⌘N
    public var showAddJobSheet: Bool = false
    /// Triggers search field focus from app menu / ⌘K
    public var focusSearch: Bool = false
    /// Triggers CSV export of the current filtered Jobs view from app menu / ⌘⇧E
    public var exportJobsRequested: Bool = false
    /// Which tab the ⌘, Settings window should show. Set by deep-links (e.g. the
    /// "AI not configured" nudge) before opening the window.
    public var settingsTab: SettingsPane = .general
    /// Set by "Add Note" affordances (e.g. the Jobs row context menu) to ask the job detail view
    /// to open the selected job's Timeline tab for note entry. Cleared once consumed.
    public var composeNoteJobID: String?

    public init() {}

    /// Select a job by its `Job.id` and switch to the Jobs section.
    /// Callers that only have a public job number must resolve it to an id first
    /// (the Router has no model access).
    public func selectJob(id: String) {
        selectedSection = .jobs
        selectedJobID = id
    }

    public func navigateToSection(_ section: SidebarSection) {
        selectedSection = section
    }
}
