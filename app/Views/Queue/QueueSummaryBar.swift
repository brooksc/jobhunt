import SwiftUI
import SwiftData
import JobhuntCore

/// Small summary bar showing queue counts and a Pause/Resume toggle.
struct QueueSummaryBar: View {
    let requests: [LLMRequest]
    let isPaused: Bool
    let onTogglePause: () async -> Void

    private var queued: Int { requests.filter { $0.status == .queued }.count }
    private var running: Int { requests.filter { $0.status == .running }.count }
    private var failed: Int {
        requests.filter { $0.status == .failed || $0.status == .retryExhausted }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                countBadge(label: "Queued", count: queued, color: .blue)
                countBadge(label: "Running", count: running, color: .green)
                countBadge(label: "Failed", count: failed, color: .red)
            }

            Spacer()

            Button {
                Task { await onTogglePause() }
            } label: {
                Label(
                    isPaused ? "Resume" : "Pause",
                    systemImage: isPaused ? "play.fill" : "pause.fill"
                )
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isPaused ? .green : .orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func countBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .font(.caption)
    }
}
