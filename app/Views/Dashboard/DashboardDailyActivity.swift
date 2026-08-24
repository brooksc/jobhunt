import Charts
import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Daily activity

/// In an extension rather than the struct body purely for size: DashboardView sits at
/// SwiftLint's 500-line type limit, and adding the automatic-search card pushed it over.
/// Extensions don't count toward that, and this section is self-contained.
extension DashboardView {
    var dailyActivitySection: some View {
        let captureData = recentCaptures.map { (capturedAt: $0.capturedAt, id: $0.id) }
        let activity = DashboardMetrics.buildDailyActivity(captures: captureData, now: dayToken)

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Daily Activity (30 days)")

            GroupBox {
                if activity.isEmpty || activity.allSatisfy({ $0.count == 0 }) { // swiftlint:disable:this empty_count
                    emptyState("No activity in the last 30 days", subtitle: nil)
                        .frame(height: 120)
                } else {
                    Chart {
                        ForEach(activity, id: \.day) { item in
                            BarMark(
                                x: .value("Day", item.day, unit: .day),
                                y: .value("Captures", item.count)
                            )
                            .foregroundStyle(Theme.accent)
                            .cornerRadius(2)
                        }
                    }
                    .frame(height: 150)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) {
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Site Check-in Schedule
}
