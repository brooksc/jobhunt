import SwiftUI

// MARK: - DueBadge

/// Compact relative-due pill ("Today", "Tomor.", "in 3d", "2d late") used by the Dashboard
/// follow-ups list. Day-granular: it compares start-of-day values, so it re-renders correctly when
/// its host refreshes at a calendar-day boundary (TASK-583).
struct DueBadge: View {
    let date: Date

    private var label: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: today, to: due).day ?? 0
        if days < 0 { return "\(-days)d late" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomor." }
        return "in \(days)d"
    }

    private var color: Color {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: date)
        if due < today { return .red }
        if due == today { return .orange }
        return .secondary
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
