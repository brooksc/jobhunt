import SwiftUI
import JobhuntCore

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
        case .saved: return "Saved"
        case .applied: return "Applied"
        case .interview: return "Interview"
        case .offer: return "Offer"
        case .rejected: return "Rejected"
        case .archived: return "Archived"
        case .notAvailable: return "Not Available"
        case .duplicate: return "Duplicate"
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
