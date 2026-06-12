import Charts
import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {
    @Environment(Router.self) private var router

    /// All jobs — used for stat cards, opportunities, pipeline, quality
    @Query private var jobs: [Job]
    /// All captures in last 30 days — used for daily activity chart
    @Query private var recentCaptures: [Capture]
    /// Sites sorted by addedAt — filtered/sorted for schedule in computed property
    @Query(sort: \Site.addedAt) private var sites: [Site]

    /// Cached aggregate metrics — recomputed only when `jobs` changes, not on every render.
    @State private var summary: JobStatusSummary = .zero

    init() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        _recentCaptures = Query(
            filter: #Predicate<Capture> { capture in
                capture.capturedAt >= thirtyDaysAgo
            },
            sort: \Capture.capturedAt
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                statCardsSection
                HStack(alignment: .top, spacing: 16) {
                    pipelineFunnelSection
                    followUpsDueSection
                }
                HStack(alignment: .top, spacing: 16) {
                    recommendedToApplySection
                    recentCapturesSection
                }
                dailyActivitySection
                siteScheduleSection
                qualitySummarySection
            }
            .padding(16)
        }
        .navigationTitle("Dashboard")
        .onAppear { summary = JobStatusSummary(jobs: jobs) }
        .onChange(of: jobs) { _, updated in summary = JobStatusSummary(jobs: updated) }
    }

    // MARK: - Stat Cards

    private var statCardsSection: some View {
        HStack(spacing: 12) {
            StatCard(label: "Total Jobs", value: summary.total, systemImage: "briefcase")
            StatCard(label: "Active", value: summary.active, systemImage: "flame", color: .blue)
            StatCard(label: "Interviews", value: summary.interviews, systemImage: "person.2", color: .purple)
            StatCard(label: "Offers", value: summary.offers, systemImage: "star.fill", color: .green)
        }
    }

    // MARK: - Recommended to Apply

    private var recommendedToApplySection: some View {
        let recommended = jobs
            .filter { $0.status == .pursuing && ($0.fitScore ?? 0) > 0 }
            .sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }
            .prefix(4)

        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("Recommended to Apply")
                        .font(.subheadline.weight(.semibold))
                    Text("best fit · not yet applied")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.bottom, 10)

                if recommended.isEmpty {
                    emptyState("No scored saved jobs", subtitle: "Score saved jobs to see recommendations.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recommended)) { job in
                            Button {
                                router.selectedJobID = job.id
                                router.selectedSection = .jobs
                            } label: {
                                HStack(spacing: 12) {
                                    if let score = job.fitScore {
                                        FitRingView(score: score, size: 32)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(job.title ?? "Untitled")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        HStack(spacing: 4) {
                                            CompanyMarkView(name: job.company, size: 14)
                                            Text(job.company ?? "")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if let url = job.applicationURL ?? job.capture?.url, let link = URL(string: url) {
                                        Link("Apply", destination: link)
                                            .font(.caption2.weight(.semibold))
                                            .buttonStyle(.borderedProminent)
                                    }
                                }
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recent Captures

    private var recentCapturesSection: some View {
        let recent = Array(jobs.sorted { ($0.capture?.capturedAt ?? $0.createdAt) > ($1.capture?.capturedAt ?? $1.createdAt) }.prefix(4))

        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Recent Captures")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.bottom, 10)

                if recent.isEmpty {
                    emptyState("No jobs yet", subtitle: nil)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recent) { job in
                            Button {
                                router.selectedJobID = job.id
                                router.selectedSection = .jobs
                            } label: {
                                HStack(spacing: 8) {
                                    CompanyMarkView(name: job.company, size: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(job.title ?? "Untitled")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(job.company ?? "")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    ExtractionChip(status: job.extractionStatus)
                                    if let capturedAt = job.capture?.capturedAt {
                                        Text(capturedAt, style: .relative)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Follow-ups Due

    private var followUpsDueSection: some View {
        let now = Date()
        let dueSoon = jobs
            .filter { job in
                job.actions.contains { action in
                    action.completedAt == nil
                        && (action.snoozedUntil == nil || action.snoozedUntil! <= now)
                        && action.dueDate <= Calendar.current.date(byAdding: .day, value: 7, to: now)!
                }
            }
            .sorted { a, b in
                let aDate = a.actions.filter { $0.completedAt == nil }.map(\.dueDate).min() ?? Date.distantFuture
                let bDate = b.actions.filter { $0.completedAt == nil }.map(\.dueDate).min() ?? Date.distantFuture
                return aDate < bDate
            }
            .prefix(4)

        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Follow-ups Due")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("View all") {
                        router.selectedSection = .needsAction
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                if dueSoon.isEmpty {
                    emptyState("All caught up!", subtitle: nil)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dueSoon)) { job in
                            Button {
                                router.selectedJobID = job.id
                                router.selectedSection = .jobs
                            } label: {
                                let action = job.actions.filter { $0.completedAt == nil }.sorted { $0.dueDate < $1.dueDate }.first
                                HStack(spacing: 8) {
                                    if let action {
                                        DueBadge(date: action.dueDate)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(job.company ?? "Unknown")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let action {
                                            Text(action.note)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Pipeline Funnel (horizontal bars)

    private var pipelineFunnelSection: some View {
        let counts = summary.funnelCounts
        let maxCount = counts.map(\.count).max() ?? 1

        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Application Funnel")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.bottom, 10)

                VStack(spacing: 8) {
                    ForEach(Array(counts.enumerated()), id: \.element.label) { idx, item in
                        HStack(spacing: 10) {
                            Text(item.label)
                                .font(.caption.weight(.medium))
                                .frame(width: 64, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.1))
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(funnelColor(idx))
                                        .frame(width: max(28, geo.size.width * CGFloat(item.count) / CGFloat(max(1, maxCount))))
                                        .overlay(
                                            Text("\(item.count)")
                                                .font(.caption.weight(.bold).monospacedDigit())
                                                .foregroundStyle(.white)
                                                .padding(.leading, 8),
                                            alignment: .leading
                                        )
                                }
                            }
                            .frame(height: 24)
                            // Conversion rate
                            if idx > 0 {
                                let prev = counts[idx - 1].count
                                let conv = prev > 0 ? Int((Double(item.count) / Double(prev)) * 100) : 0
                                Text("\(conv)%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 30, alignment: .trailing)
                            } else {
                                Spacer().frame(width: 30)
                            }
                        }
                    }
                }

                Divider().padding(.vertical, 10)

                // Footer stats
                HStack(spacing: 0) {
                    FooterCell(label: "Avg fit", value: summary.avgFitDisplay)
                    FooterCell(label: "Rejected", value: "\(summary.rejected)")
                    FooterCell(label: "Passed", value: "\(summary.passed)", last: true)
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity)
    }

    private func funnelColor(_ index: Int) -> Color {
        switch index {
        case 0: return .accentColor.opacity(0.6)
        case 1: return .accentColor.opacity(0.75)
        case 2: return .blue.opacity(0.75)
        case 3: return .green.opacity(0.75)
        default: return .accentColor
        }
    }

    // MARK: - Daily Activity (30 days)

    private var dailyActivitySection: some View {
        let captureData = recentCaptures.map { (capturedAt: $0.capturedAt, id: $0.id) }
        let activity = DashboardMetrics.buildDailyActivity(captures: captureData)

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

    private var siteScheduleSection: some View {
        let now = Date()
        let upcoming: [(site: Site, overdue: Bool)] = sites
            .compactMap { site -> (site: Site, overdue: Bool)? in
                guard let reviewAt = site.nextReviewAt else { return nil }
                return (site: site, overdue: reviewAt < now)
            }
            .sorted { $0.site.nextReviewAt ?? now < $1.site.nextReviewAt ?? now }
            .prefix(5)
            .map(\.self)

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Site Check-in Schedule")

            GroupBox {
                if upcoming.isEmpty {
                    emptyState("No sites scheduled", subtitle: "Add sites to track companies to revisit.")
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(upcoming.enumerated()), id: \.element.site.id) { index, item in
                            Button {
                                router.selectedSiteID = item.site.id
                                router.selectedSection = .sites
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(item.overdue ? Color.red : Color.green)
                                        .frame(width: 8, height: 8)
                                    Text(item.site.companyName ?? item.site.pageTitle)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    if let nextReview = item.site.nextReviewAt {
                                        Text(nextReview, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(item.overdue ? .red : .secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < upcoming.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Quality Summary

    private var qualitySummarySection: some View {
        QualitySummarySection(issueCount: summary.issueCount)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func emptyState(_ message: String, subtitle: String?) -> some View {
        VStack(spacing: 6) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let label: String
    let value: Int
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text("\(value)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - DueBadge

private struct DueBadge: View {
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

// MARK: - FooterCell

private struct FooterCell: View {
    let label: String
    let value: String
    var last = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.3)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .overlay(
            last ? nil : Divider().frame(maxHeight: .infinity).padding(.vertical, 4),
            alignment: .trailing
        )
    }
}

// MARK: - QualitySummarySection

/// Separate view so it can own its own @Environment access and async Task context.
private struct QualitySummarySection: View {
    let issueCount: Int
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quality Summary")
                .font(.headline)

            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(issueCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(issueCount == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        Text("Jobs with extraction issues")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        if issueCount > 0 {
                            Button("View LLM Queue") {
                                router.selectedSection = .llmQueue
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Review quality") {
                            router.selectedSection = .dataQuality
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationSplitView {
        Text("Sidebar")
    } content: {
        DashboardView()
    } detail: {
        Text("Detail")
    }
    .environment(Router())
    .environment(Theme())
}
