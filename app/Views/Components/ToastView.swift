import SwiftUI

struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
    /// Optional inline action (e.g. "Undo"). When set, a button renders in the toast.
    var actionLabel: String?
    var action: (() -> Void)?
    /// Coalescing key — showing another toast with the same key replaces this one in place instead of
    /// stacking a duplicate (e.g. repeated "N still selected" messages).
    var key: String?

    /// Actionable and error toasts stay until the user acts or dismisses them; plain informational
    /// toasts auto-fade. So feedback the user might want to act on never disappears out from under them.
    var isPersistent: Bool { action != nil || isError }
}

struct ErrorRecord: Identifiable {
    let id = UUID()
    let message: String
    let timestamp: Date
}

@Observable
final class ToastStore {
    var messages: [ToastMessage] = []
    /// Last 10 error toasts — survives dismissal for the Debug tab.
    private(set) var recentErrors: [ErrorRecord] = []

    /// Max simultaneously-visible toasts — beyond this, the oldest non-persistent (then oldest) toasts
    /// are trimmed so a burst can't bury the window in a stack.
    private let maxVisible = 3

    func show(
        _ message: String,
        isError: Bool = false,
        key: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        let toast = ToastMessage(message: message, isError: isError, actionLabel: actionLabel, action: action, key: key)
        // Coalesce by key: a keyed message replaces the existing one in place rather than stacking.
        if let key, let index = messages.firstIndex(where: { $0.key == key }) {
            messages[index] = toast
        } else {
            messages.append(toast)
        }
        if isError {
            recentErrors.append(ErrorRecord(message: message, timestamp: Date()))
            if recentErrors.count > 10 { recentErrors.removeFirst() }
        }
        trimStack()
        // Only plain informational toasts auto-fade; actionable/error toasts persist until dismissed.
        if !toast.isPersistent {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                messages.removeAll { $0.id == toast.id }
            }
        }
    }

    func dismiss(_ id: UUID) {
        messages.removeAll { $0.id == id }
    }

    /// Bound the visible stack: drop the oldest non-persistent toast first, then the oldest overall.
    private func trimStack() {
        while messages.count > maxVisible {
            if let index = messages.firstIndex(where: { !$0.isPersistent }) {
                messages.remove(at: index)
            } else {
                messages.removeFirst()
            }
        }
    }
}

struct ToastView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .red : .green)
            Text(toast.message)
                .font(.callout)
            Spacer()
            if let label = toast.actionLabel, let action = toast.action {
                Button(label) {
                    action()
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
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4, y: 2)
    }
}

struct ToastOverlay: View {
    let store: ToastStore

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.messages) { toast in
                ToastView(toast: toast) {
                    store.dismiss(toast.id)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding()
        .animation(.spring(response: 0.3), value: store.messages.map(\.id))
    }
}

#Preview {
    let store = ToastStore()
    return VStack {
        Button("Show Toast") { store.show("Job saved successfully") }
        Button("Show Error") { store.show("Failed to save job", isError: true) }
    }
    .frame(width: 400, height: 300)
    .overlay(alignment: .bottom) {
        ToastOverlay(store: store)
    }
}
