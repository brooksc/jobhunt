import JobhuntCore
import SwiftUI

/// The paused-queue banner (TASK-524).
///
/// Auto-pauses read as warnings; a deliberate pause is a decision, not a problem, so it takes the
/// same shape in a neutral colour. Whether to show it at all is decided by `QueuePauseBanner` in
/// Core — this only draws what that returned.
struct QueuePauseBannerView: View {
    let banner: QueuePauseBanner
    let onResume: () -> Void

    private var tint: Color {
        banner.isAutomatic ? .orange : .secondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: banner.isAutomatic ? "exclamationmark.triangle.fill" : "pause.circle.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.callout.weight(.medium))
                Text(banner.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Resume", action: onResume)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(banner.isAutomatic ? 0.12 : 0.06))
        .accessibilityIdentifier("queue.pauseBanner")
    }
}
