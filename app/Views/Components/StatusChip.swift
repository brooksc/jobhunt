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

private extension JobStatus {
    var displayName: String {
        switch self {
        case .saved: "Saved"
        case .applied: "Applied"
        case .interview: "Interview"
        case .offer: "Offer"
        case .rejected: "Rejected"
        case .archived: "Archived"
        case .notAvailable: "Not Available"
        case .duplicate: "Duplicate"
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
