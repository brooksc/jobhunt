import SwiftUI

// MARK: - NotificationCenterView (TASK-645)

/// The bell popover: the durable list of actionable + error notifications, newest first, each with its
/// inline action (Undo/Review) and a relative time, plus Clear All. This is where feedback lives after
/// its brief transient toast fades — so nothing is missed and nothing needs manual dismissal mid-flurry.
struct NotificationCenterView: View {
    let store: ToastStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notifications\(store.notifications.isEmpty ? "" : " (\(store.notifications.count))")")
                    .font(.headline)
                Spacer()
                if !store.notifications.isEmpty {
                    Button("Clear All") { store.clearAll() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            Divider()

            if store.notifications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash").font(.title2).foregroundStyle(.tertiary)
                    Text("No notifications").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.notifications) { notification in
                            row(notification)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 340, height: store.notifications.isEmpty ? 170 : 380)
    }

    private func row(_ notification: AppNotification) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notification.kind == .error ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notification.kind == .error ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.message).font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Text(notification.createdAt, style: .relative)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            if let label = notification.actionLabel, !notification.actions.isEmpty {
                Button(label) { store.runAction(notification.id) }
                    .font(.caption.weight(.semibold))
            }
            Button { store.remove(notification.id) } label: {
                Image(systemName: "xmark").font(.caption2).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
