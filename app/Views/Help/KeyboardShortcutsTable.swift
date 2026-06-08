import SwiftUI

struct KeyboardShortcutsTable: View {
    private let shortcuts: [(shortcut: String, action: String)] = [
        ("⌘K", "Open search / jump to Jobs"),
        ("↑ / ↓", "Previous / next job in list"),
        ("↩", "Open selected job detail"),
        ("⎋", "Close panel / clear search"),
        ("⌘,", "Open Settings"),
        ("⌘N", "New capture (from browser)"),
        ("⌘⇧E", "Export jobs to CSV"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow {
                Text("Shortcut")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text("Action")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            ForEach(shortcuts, id: \.shortcut) { row in
                GridRow {
                    Text(row.shortcut)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.accent)
                    Text(row.action)
                        .font(.body)
                }
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                    .foregroundStyle(Color.secondary.opacity(0.3))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    KeyboardShortcutsTable()
        .padding()
        .frame(width: 400)
}
