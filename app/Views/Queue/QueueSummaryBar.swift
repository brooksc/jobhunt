import JobhuntCore
import SwiftData
import SwiftUI

/// Small summary bar showing queue counts and a Pause/Resume toggle.
struct QueueSummaryBar: View {
    let requests: [LLMRequest]
    /// All non-terminal requests (finishedAt == nil) — used for accurate queued/running counts
    /// regardless of how many terminal rows exist beyond the display window.
    let activeRequests: [LLMRequest]
    let isPaused: Bool
    let onTogglePause: () async -> Void

    private var queued: Int {
        activeRequests.count(where: { $0.status == .queued })
    }

    private var running: Int {
        activeRequests.count(where: { $0.status == .running })
    }

    private var failed: Int {
        requests.count(where: { $0.status == .failed || $0.status == .retryExhausted })
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
