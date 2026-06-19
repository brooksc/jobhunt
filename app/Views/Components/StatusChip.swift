import JobhuntCore
import SwiftUI

struct StatusChip: View {
    let status: JobStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.statusColor(status).opacity(0.15))
            .foregroundStyle(Theme.statusColor(status))
            .clipShape(Capsule())
    }
}

extension JobStatus {
    var displayName: String {
        switch self {
        case .new: "New"
        case .pursuing: "Interested" // display only — stored rawValue stays "pursuing" (no migration)
        case .applied: "Applied"
        case .interview: "Interview"
        case .offer: "Offer"
        case .rejected: "Rejected"
        case .passed: "Passed"
        case .archived: "Archived"
        case .closed: "Closed"
        case .duplicate: "Duplicate"
        case .expired: "Expired"
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(JobStatus.allCases, id: \.self) { status in
            StatusChip(status: status)
        }
    }
    .padding()
}
