import SwiftUI

struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
    /// Optional inline action (e.g. "Undo"). When set, a button renders in the toast.
    var actionLabel: String?
    var action: (() -> Void)?
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

    func show(
        _ message: String,
        isError: Bool = false,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        let toast = ToastMessage(message: message, isError: isError, actionLabel: actionLabel, action: action)
        messages.append(toast)
        if isError {
            recentErrors.append(ErrorRecord(message: message, timestamp: Date()))
            if recentErrors.count > 10 { recentErrors.removeFirst() }
        }
        // Give actionable toasts (e.g. Undo) longer to be clicked.
        let seconds = action == nil ? 3 : 6
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            messages.removeAll { $0.id == toast.id }
        }
    }

    func dismiss(_ id: UUID) {
        messages.removeAll { $0.id == id }
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
