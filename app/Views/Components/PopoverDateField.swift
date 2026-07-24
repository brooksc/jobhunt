import SwiftUI

// MARK: - PopoverDateField (TASK-644 review + audit)

/// A click-driven date field: a labeled button showing the date that opens a graphical calendar in a
/// popover. Prefer this over a bare `DatePicker` inside a **sheet** — the default macOS date picker is a
/// segmented field editor that needs keyboard first-responder to change a month/day/year segment, and a
/// window presenting several stacked sheets can leave that responder broken, so dates become
/// uneditable. A popover manages its own window/responder, so clicking a day always works.
struct PopoverDateField: View {
    let label: String
    @Binding var date: Date
    /// Earliest allowed date (a one-sided range — crash-safe on odd data, unlike a two-sided range that
    /// can invert). Optional.
    var lowerBound: Date?

    @State private var showPicker = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button(date.formatted(date: .abbreviated, time: .omitted)) { showPicker = true }
                .buttonStyle(.bordered)
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    Group {
                        if let lowerBound {
                            DatePicker(label, selection: $date, in: lowerBound..., displayedComponents: .date)
                        } else {
                            DatePicker(label, selection: $date, displayedComponents: .date)
                        }
                    }
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .frame(minWidth: 260)
                    // Close the calendar as soon as a day is picked.
                    .onChange(of: date) { _, _ in showPicker = false }
                }
        }
    }
}
