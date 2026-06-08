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
        case .dashboard: "Dashboard"
        case .jobs: "Jobs"
        case .dataQuality: "Data Quality"
        case .needsAction: "Needs Action"
        case .llmQueue: "LLM Queue"
        case .sites: "Sites"
        case .duplicates: "Duplicates"
        case .settings: "Settings"
        case .help: "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar"
        case .jobs: "briefcase"
        case .dataQuality: "checkmark.shield"
        case .needsAction: "bell"
        case .llmQueue: "cpu"
        case .sites: "globe"
        case .duplicates: "doc.on.doc"
        case .settings: "gear"
        case .help: "questionmark.circle"
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

    public func navigateToJob(number _: Int) {
        selectedSection = .jobs
        // selectedJobID will be set by the jobs list when it finds the matching job
        selectedJobID = nil
    }

    public func navigateToSection(_ section: SidebarSection) {
        selectedSection = section
    }
}
