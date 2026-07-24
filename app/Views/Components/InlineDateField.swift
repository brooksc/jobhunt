import SwiftUI

// MARK: - InlineDateField (TASK-644 review + audit)

/// A click-driven date field for use inside a **sheet**: a labeled button showing the date that
/// expands an inline graphical calendar below it. Two macOS pitfalls this avoids:
///   1. The default `DatePicker` (segmented field editor) needs keyboard first-responder to change a
///      month/day/year segment, which a window with several stacked sheets can leave broken.
///   2. A `.popover` inside a sheet **crashes** on macOS 26/27 (`NSPopover` ordering a child window as a
///      sheet throws during layout), so the calendar is shown inline, not in a popover.
/// The graphical picker is pure click interaction, so it works regardless of the sheet's responder.
struct InlineDateField: View {
    let label: String
    @Binding var date: Date
    /// Earliest allowed date (a one-sided range — crash-safe on odd data, unlike a two-sided range that
    /// can invert). Optional.
    var lowerBound: Date?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("dateField.\(label)")
            }
            if expanded {
                Group {
                    if let lowerBound {
                        DatePicker(label, selection: $date, in: lowerBound..., displayedComponents: .date)
                    } else {
                        DatePicker(label, selection: $date, displayedComponents: .date)
                    }
                }
                .datePickerStyle(.graphical)
                .labelsHidden()
                // Collapse once a day is picked.
                .onChange(of: date) { _, _ in withAnimation { expanded = false } }
            }
        }
    }
}
