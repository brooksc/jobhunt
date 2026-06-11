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
    case savedSearch(String)
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
    /// Triggers CSV export from app menu / ⌘⇧E
    public var triggerExport: Bool = false

    public init() {}

    public func navigateToJob(number _: Int) {
        selectedSection = .jobs
        selectedJobID = nil
    }

    public func navigateToSection(_ section: SidebarSection) {
        selectedSection = section
    }
}
