import JobhuntCore
import SwiftUI

/// App-wide attention banner for a queue problem the user must act on — e.g. a rejected API key
/// (TASK-542). Rendered at the top of the window from *any* screen, driven by `Router.queueAlert`,
/// so the user sees it whether they're on Jobs, Dashboard, or anywhere else (not only the LLM Queue).
struct QueueAlertBanner: View {
    let alert: QueueAlert
    /// Passed explicitly, NOT read from @Environment: this banner is rendered inside a `.safeAreaInset`
    /// applied *after* ContentView's `.environment(router)`, so the inset content is outside that
    /// scope — reading `@Environment(Router.self)` here traps with "Observable not found".
    let router: Router
    let onDismiss: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(alert.message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if alert.showsAISettings {
                Button("Open AI Settings") {
                    router.settingsTab = .llm
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Button("Dismiss", action: onDismiss)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.red.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}
