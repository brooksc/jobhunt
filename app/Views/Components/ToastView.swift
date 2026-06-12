import SwiftUI

struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
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

    func show(_ message: String, isError: Bool = false) {
        let toast = ToastMessage(message: message, isError: isError)
        messages.append(toast)
        if isError {
            recentErrors.append(ErrorRecord(message: message, timestamp: Date()))
            if recentErrors.count > 10 { recentErrors.removeFirst() }
        }
        // Auto-dismiss after 3 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
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
