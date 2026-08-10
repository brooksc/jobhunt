import SwiftUI

// MARK: - AppNotification (TASK-645)

/// A single notification. It shows briefly as a transient corner toast and — when it's actionable
/// (Undo/Review) or an error — is also kept as a durable entry in the bell notification center, so
/// nothing vanishes before you can act and nothing has to be manually dismissed. Repeated same-`key`
/// actions within a short window coalesce into one entry with a combined Undo-all.
struct AppNotification: Identifiable {
    enum Kind { case info, action, error }
    let id = UUID()
    var message: String
    var kind: Kind
    var createdAt: Date
    /// Coalescing group key — same-key actionable notifications within the window merge (e.g. "archive").
    var key: String?
    /// Accumulated item count across merged actions (drives the "Updated N jobs" group message).
    var count: Int
    var actionLabel: String?
    /// One closure per merged action; the entry's action runs them all (Undo-all).
    var actions: [() -> Void]

    /// Bell entries are the actionable / error notifications worth keeping; plain info is transient-only.
    var isPersistent: Bool {
        kind == .error || !actions.isEmpty
    }
}

struct ErrorRecord: Identifiable {
    let id = UUID()
    let message: String
    let timestamp: Date
}

// MARK: - ToastStore / notification center

@Observable
final class ToastStore {
    /// Bell inbox — actionable + error notifications, newest first. Durable until undone or cleared.
    private(set) var notifications: [AppNotification] = []
    /// The single transient toast currently shown in the corner (nil = none). Auto-fades.
    private(set) var transient: AppNotification?
    /// Last 10 error toasts — survives dismissal for the Debug tab.
    private(set) var recentErrors: [ErrorRecord] = []

    /// Recent same-key actions merge into one bell entry within this window.
    private let coalesceWindow: TimeInterval = 30
    /// Monotonic token so a re-shown/coalesced transient isn't cleared early by an older fade timer.
    private var transientToken = 0

    /// Show a notification. Non-actionable info is transient-only; actionable/error notifications also
    /// land in the bell. `itemCount` + `groupMessage` drive coalescing of repeated same-`key` actions.
    func show(
        _ message: String,
        isError: Bool = false,
        key: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil,
        itemCount: Int = 1,
        groupMessage: ((Int) -> String)? = nil
    ) {
        let now = Date()
        if isError { recordError(message, at: now) }

        // Coalesce into a recent same-key persistent entry (combined Undo-all).
        if let key, action != nil || isError,
           let idx = notifications.firstIndex(where: { $0.key == key }),
           now.timeIntervalSince(notifications[idx].createdAt) <= coalesceWindow {
            var entry = notifications.remove(at: idx)
            entry.count += itemCount
            if let action { entry.actions.append(action) }
            entry.message = groupMessage?(entry.count) ?? message
            entry.createdAt = now
            if isError { entry.kind = .error }
            notifications.insert(entry, at: 0)
            showTransient(entry)
            return
        }

        let kind: AppNotification.Kind = isError ? .error : (action != nil ? .action : .info)
        let entry = AppNotification(
            message: message, kind: kind, createdAt: now, key: key, count: itemCount,
            actionLabel: actionLabel, actions: action.map { [$0] } ?? []
        )
        if entry.isPersistent { notifications.insert(entry, at: 0) }
        showTransient(entry)
    }

    /// Run a bell entry's combined action(s) (Undo-all) and remove it.
    func runAction(_ id: UUID) {
        guard let entry = notifications.first(where: { $0.id == id }) else { return }
        entry.actions.forEach { $0() }
        remove(id)
    }

    func remove(_ id: UUID) {
        notifications.removeAll { $0.id == id }
        if transient?.id == id { transient = nil }
    }

    func dismissTransient() {
        transient = nil
    }

    func clearAll() {
        notifications.removeAll()
        transient = nil
    }

    private func showTransient(_ entry: AppNotification) {
        transient = entry
        transientToken &+= 1
        let token = transientToken
        let seconds: Double = entry.kind == .error ? 5 : 4
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if transientToken == token { transient = nil }
        }
    }

    private func recordError(_ message: String, at now: Date) {
        recentErrors.append(ErrorRecord(message: message, timestamp: now))
        if recentErrors.count > 10 { recentErrors.removeFirst() }
    }
}

// MARK: - Transient corner toast

struct ToastView: View {
    let notification: AppNotification
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notification.kind == .error ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notification.kind == .error ? .red : .green)
            Text(notification.message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let label = notification.actionLabel, !notification.actions.isEmpty {
                Button(label) {
                    onAction()
                    onDismiss()
                }
                .font(.callout.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4, y: 2)
    }
}

/// The corner overlay — at most ONE transient toast at a time, so a burst can't cover the content.
struct ToastOverlay: View {
    let store: ToastStore

    var body: some View {
        if let toast = store.transient {
            ToastView(
                notification: toast,
                onAction: { store.runAction(toast.id) },
                onDismiss: { store.dismissTransient() }
            )
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: toast.id)
        }
    }
}

#Preview {
    let store = ToastStore()
    return VStack(spacing: 12) {
        Button("Show Toast") { store.show("Job saved successfully") }
        Button("Show Undo") { store.show("Status set to Interview", actionLabel: "Undo", action: {}) }
        Button("Show Error") { store.show("Failed to save job", isError: true) }
    }
    .frame(width: 400, height: 300)
    .overlay(alignment: .bottomTrailing) {
        ToastOverlay(store: store)
    }
}
