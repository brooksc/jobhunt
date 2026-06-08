import Foundation
import JobhuntCore

enum JobsSortKey: String, CaseIterable {
    case jobNumber
    case company
    case title
    case status
    case fitScore
    case rating
    case capturedAt
    case extractedAt
}

struct JobsFilterState: Equatable {
    var statusFilter: Set<JobStatus>? // nil means "All"
    var searchText: String = ""
    var sortKey: JobsSortKey = .capturedAt
    var sortAscending: Bool = false
}
