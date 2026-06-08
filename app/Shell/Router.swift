import SwiftUI

public enum SidebarSection: String, CaseIterable, Hashable {
    case dashboard
    case jobs
    case dataQuality
    case needsAction
    case llmQueue
    case sites
    case duplicates
    case settings
    case help

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .jobs: return "Jobs"
        case .dataQuality: return "Data Quality"
        case .needsAction: return "Needs Action"
        case .llmQueue: return "LLM Queue"
        case .sites: return "Sites"
        case .duplicates: return "Duplicates"
        case .settings: return "Settings"
        case .help: return "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar"
        case .jobs: return "briefcase"
        case .dataQuality: return "checkmark.shield"
        case .needsAction: return "bell"
        case .llmQueue: return "cpu"
        case .sites: return "globe"
        case .duplicates: return "doc.on.doc"
        case .settings: return "gear"
        case .help: return "questionmark.circle"
        }
    }
}

@Observable
public final class Router {
    public var selectedSection: SidebarSection = .jobs
    public var selectedJobID: String?
    public var selectedSiteID: String?
    public var statusFilter: String?
    public var searchText: String = ""

    public init() {}

    public func navigateToJob(number: Int) {
        selectedSection = .jobs
        // selectedJobID will be set by the jobs list when it finds the matching job
        selectedJobID = nil
    }

    public func navigateToSection(_ section: SidebarSection) {
        selectedSection = section
    }
}
