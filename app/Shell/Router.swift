import JobhuntCore
import SwiftUI

public enum SidebarSection: String, CaseIterable, Hashable {
    case dashboard
    case jobs
    case dataQuality
    case needsAction
    case llmQueue
    case sites
    case duplicates
    case help
    case settings

    var title: String {
        switch self {
        case .dashboard:   "Dashboard"
        case .jobs:        "Jobs"
        case .dataQuality: "Data Quality"
        case .needsAction: "Needs Action"
        case .llmQueue:    "LLM Queue"
        case .sites:       "Sites"
        case .duplicates:  "Duplicates"
        case .help:        "Help"
        case .settings:    "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:   "chart.bar"
        case .jobs:        "briefcase"
        case .dataQuality: "checkmark.shield"
        case .needsAction: "bell"
        case .llmQueue:    "cpu"
        case .sites:       "globe"
        case .duplicates:  "doc.on.doc"
        case .help:        "questionmark.circle"
        case .settings:    "gear"
        }
    }
}

/// Typed selection value for the sidebar List. Maps to router state.
public enum SidebarItem: Hashable, Sendable {
    case dashboard
    case needsAction
    case jobsAll
    case jobs(JobStatus)
    case sites
    case duplicates
    case llmQueue
    case dataQuality
    case settings
    case help
    case savedSearch(String)

    /// The display label shown in the sidebar row (matches NSTextField text for AppKit selection).
    var sidebarLabel: String? {
        switch self {
        case .dashboard:         return "Dashboard"
        case .needsAction:       return "Needs Action"
        case .jobsAll:           return "All Jobs"
        case .jobs(let status):  return status.displayName
        case .sites:             return "Sites"
        case .duplicates:        return "Duplicates"
        case .llmQueue:          return "LLM Queue"
        case .dataQuality:       return "Data Quality"
        case .settings:          return "Settings"
        case .help:              return "Help"
        case .savedSearch:       return nil  // dynamic name — caller handles
        }
    }
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
