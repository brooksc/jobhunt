import SwiftUI

// MARK: - SheetDateField (TASK-644 review)

/// The app's single date-entry control for sheet-hosted forms: a labeled button showing the current
/// date that opens a graphical calendar in a popover and closes as soon as a day is picked.
///
/// Two things this deliberately gets right:
///   1. **Click-driven.** The default segmented `DatePicker` needs keyboard first-responder to change a
///      month/day/year segment, which a window with several coexisting sheets can leave broken.
///   2. **Bounds are crash-safe.** A `ClosedRange` traps at runtime when `lower > upper`, which is
///      reachable whenever a stored date sits outside the bounds its siblings imply, so an inverted
///      range falls back to an unbounded picker rather than trapping.
///
/// (An earlier revision expanded the calendar inline to dodge a `.popover`-inside-`.sheet` crash seen on
/// macOS 27.0 beta1; that was a beta regression — fixed in beta2 — and inline expansion pushed later
/// fields off the sheet, so the native popover is back.)
struct SheetDateField: View {
    let label: String
    @Binding var date: Date
    /// Earliest / latest allowed date. Either may be nil for a one-sided or unbounded field.
    var lowerBound: Date?
    var upperBound: Date?

    @State private var showPicker = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            // Assignment, not a toggle: a transient popover dismisses on any outside click — including
            // this button — so toggling would close and immediately reopen it.
            Button { showPicker = true } label: {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                Image(systemName: "calendar").font(.caption2)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("dateField.\(label)")
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                picker
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(minWidth: 260)
                    .padding()
                    .onChange(of: date) { _, _ in showPicker = false }
            }
        }
    }

    @ViewBuilder private var picker: some View {
        if let lowerBound, let upperBound {
            if lowerBound <= upperBound {
                DatePicker(label, selection: $date, in: lowerBound ... upperBound, displayedComponents: .date)
            } else {
                DatePicker(label, selection: $date, displayedComponents: .date)
            }
        } else if let lowerBound {
            DatePicker(label, selection: $date, in: lowerBound..., displayedComponents: .date)
        } else if let upperBound {
            DatePicker(label, selection: $date, in: ...upperBound, displayedComponents: .date)
        } else {
            DatePicker(label, selection: $date, displayedComponents: .date)
        }
    }
}
