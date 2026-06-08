import SwiftUI
import JobhuntCore

struct ExtractionChip: View {
    let status: ExtractionStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .running {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            } else {
                Image(systemName: status.systemImage)
                    .font(.caption2)
            }
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.extractionColor(status).opacity(0.15))
        .foregroundStyle(Theme.extractionColor(status))
        .clipShape(Capsule())
    }
}

private extension ExtractionStatus {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Extracting"
        case .succeeded: return "Extracted"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .running: return "arrow.trianglehead.2.clockwise"
        case .succeeded: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .skipped: return "forward.circle"
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(ExtractionStatus.allCases, id: \.self) { status in
            ExtractionChip(status: status)
        }
    }
    .padding()
}
