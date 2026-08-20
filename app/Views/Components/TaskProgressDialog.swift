import SwiftUI

// MARK: - TaskProgressDialog (TASK-640)

/// Observable progress for a long-running, user-initiated task shown in a modal dialog. Mutated on the
/// main actor (the worker hops to `MainActor` to report progress), so it's `Sendable` for the callback.
@MainActor
@Observable
final class TaskProgressModel {
    let title: String
    var current: Int = 0
    /// Total units; `<= 0` renders an indeterminate spinner (e.g. a single-shot scan with no per-item count).
    var total: Int
    var onCancel: () -> Void = {}

    /// When set, the task finished with nothing to act on — the dialog shows this message + a Done
    /// button (instead of a transient toast) so the result is stated where the user is already looking.
    var completion: String?
    var onDone: () -> Void = {}

    /// One line explaining a total that doesn't match what the user was offered.
    ///
    /// The availability check is the case this exists for: the menu offers "Check Availability of 400
    /// Shown", then the dialog counts to 342, because LinkedIn is checked a capped dozen at a time by
    /// rotation. Both numbers are correct and the difference is deliberate, but a bare "50 / 342"
    /// after asking for 400 reads as jobs having gone missing.
    var note: String?

    init(title: String, total: Int) {
        self.title = title
        self.total = total
    }

    var isIndeterminate: Bool {
        total <= 0
    }

    var fraction: Double {
        total > 0 ? min(1, Double(current) / Double(total)) : 0
    }
}

/// A centered modal showing a long task's progress with a Cancel — so tasks like the availability check
/// aren't a silent minute. Determinate (n / total) when the total is known, otherwise a spinner.
struct TaskProgressDialog: View {
    let model: TaskProgressModel

    var body: some View {
        VStack(spacing: 16) {
            Text(model.title)
                .font(.headline)
            if let completion = model.completion {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(completion).multilineTextAlignment(.center)
                }
                Button("Done") { model.onDone() }
                    .keyboardShortcut(.defaultAction)
            } else if model.isIndeterminate {
                ProgressView()
                    .controlSize(.large)
                    .padding(.vertical, 6)
                Button("Cancel", role: .cancel) { model.onCancel() }
                    .keyboardShortcut(.cancelAction)
            } else {
                ProgressView(value: model.fraction)
                    .progressViewStyle(.linear)
                Text("\(model.current) / \(model.total)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let note = model.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Cancel", role: .cancel) { model.onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 320)
        .interactiveDismissDisabled()
    }
}
