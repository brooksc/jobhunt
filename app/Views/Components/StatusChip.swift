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

// `JobStatus.displayName` now lives in JobhuntCore (JobStatus+Display.swift) so the same
// vocabulary is shared by every surface and is unit-testable.

#Preview {
    VStack(spacing: 8) {
        ForEach(JobStatus.allCases, id: \.self) { status in
            StatusChip(status: status)
        }
    }
    .padding()
}
