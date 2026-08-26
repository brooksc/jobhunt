import JobhuntCore
import SwiftUI

/// The window's status bar: what is happening, and the last thing that happened (TASK-704).
///
/// **HIG shape.** Ongoing background activity belongs somewhere quiet and permanent — Finder's
/// status bar, Mail's activity area — rather than in an alert or a floating panel, which are for
/// things that need an answer. So this is a `.safeAreaInset` on the window's bottom edge using the
/// system `.bar` material and a `Divider`, with no custom chrome: per the "justify any custom bar"
/// rule, there is nothing here that a system component doesn't already provide.
///
/// **It also rehomes the transient toast.** A floating capsule in the corner is a web and iOS
/// pattern; on the Mac the same information belongs in the status area. Nothing is lost, because
/// `ToastStore` already routes anything actionable or failed to the bell inbox as well — this only
/// changes where the passing message is drawn, and it keeps the inline action so an Undo is still
/// one click.
///
/// **Progress is determinate only when it really is.** An indeterminate spinner is the honest
/// rendering of work whose end isn't known, and inventing a bar for it is the specific thing the
/// HIG warns against.
struct StatusBar: View {
    // Passed explicitly rather than read from `@Environment`: `.safeAreaInset` content is built
    // outside the host view's environment, so an `@Environment(AppServices.self)` here resolves to
    // nothing and traps at runtime — which the compiler will not catch.
    let activity: ActivityCenter
    let toasts: ToastStore
    let jobCount: Int
    let discoveredToday: Int
    /// Extraction and fit-scoring work still outstanding. Read from the store by the host rather
    /// than mirrored into `ActivityCenter`: SwiftData already publishes this number, and keeping a
    /// second imperative copy is how the two come to disagree.
    let queuedAIRequests: Int
    let aiPaused: Bool
    var onOpen: (SidebarSection) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            activitySide
            Spacer(minLength: 12)
            messageSide
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(minHeight: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
    }

    // MARK: - Left: what's happening

    @ViewBuilder
    private var activitySide: some View {
        if let current = activity.primary {
            let row = HStack(spacing: 6) {
                if current.isDeterminate {
                    ProgressView(value: current.fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 90)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                }
                Text(current.title)
                    .foregroundStyle(.primary)
                if let detail = current.detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                if activity.activities.count > 1 {
                    Text("+\(activity.activities.count - 1)")
                        .foregroundStyle(.secondary)
                        .help("\(activity.activities.count) background tasks running")
                }
            }
            .lineLimit(1)

            if let section = current.section {
                Button { onOpen(section) } label: { row }
                    .buttonStyle(.plain)
                    .help("Show \(current.title)")
            } else {
                row
            }
        } else if queuedAIRequests > 0 {
            Button { onOpen(.llmQueue) } label: {
                HStack(spacing: 6) {
                    if aiPaused {
                        Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                    } else {
                        ProgressView().progressViewStyle(.circular).controlSize(.mini)
                    }
                    // A paused queue with work in it is the case worth naming: it looks identical
                    // to a busy one from the outside, and stays that way until someone notices.
                    Text(aiPaused
                        ? "AI paused — \(queuedAIRequests) waiting"
                        : "Reading \(queuedAIRequests) job\(queuedAIRequests == 1 ? "" : "s") with AI")
                    .foregroundStyle(aiPaused ? .primary : .secondary)
                }
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Show the AI queue")
        } else {
            // The resting state still says something true. A bar that is blank when idle reads as
            // broken, and "nothing is running" is worth stating on a feature that works unattended.
            Text(idleSummary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var idleSummary: String {
        var parts = ["\(jobCount.formatted()) job\(jobCount == 1 ? "" : "s")"]
        if discoveredToday > 0 {
            parts.append("\(discoveredToday) found today")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Right: the last thing that happened

    @ViewBuilder
    private var messageSide: some View {
        if let toast = toasts.transient {
            HStack(spacing: 6) {
                if toast.kind == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text(toast.message)
                    .foregroundStyle(toast.kind == .error ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let label = toast.actionLabel {
                    Button(label) { toasts.runAction(toast.id) }
                        .buttonStyle(.link)
                }
                Button {
                    toasts.dismissTransient()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
            }
            .frame(maxWidth: 460, alignment: .trailing)
            // Respects Reduce Motion automatically: SwiftUI downgrades this to a cross-fade.
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: toast.id)
        }
    }
}
