import SwiftUI
import SwiftData
import Charts
import JobhuntCore

// MARK: - DashboardView

struct DashboardView: View {
    @Environment(Router.self) private var router

    // All jobs — used for stat cards, opportunities, pipeline, quality
    @Query private var jobs: [Job]
    // All captures in last 30 days — used for daily activity chart
    @Query private var recentCaptures: [Capture]
    // Sites sorted by addedAt — filtered/sorted for schedule in computed property
    @Query(sort: \Site.addedAt) private var sites: [Site]

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
                topOpportunitiesSection
                pipelineFunnelSection
                dailyActivitySection
                siteScheduleSection
                qualitySummarySection
            }
            .padding(16)
        }
        .navigationTitle("Dashboard")
    }

    // MARK: - Stat Cards

    private var statCardsSection: some View {
        let total = jobs.count
        let active = jobs.filter { [.saved, .applied, .interview].contains($0.status) }.count
        let interviews = jobs.filter { $0.status == .interview }.count
        let offers = jobs.filter { $0.status == .offer }.count

        return HStack(spacing: 12) {
            StatCard(label: "Total Jobs", value: total, systemImage: "briefcase")
            StatCard(label: "Active", value: active, systemImage: "flame", color: .blue)
            StatCard(label: "Interviews", value: interviews, systemImage: "person.2", color: .purple)
            StatCard(label: "Offers", value: offers, systemImage: "star.fill", color: .green)
        }
    }

    // MARK: - Top Opportunities

    private var topOpportunitiesSection: some View {
        let opportunities = jobs
            .filter { ($0.fitScore ?? 0) > 70 && $0.status != .rejected && $0.status != .archived }
            .sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }
            .prefix(4)

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Top Opportunities")

            if opportunities.isEmpty {
                emptyState("No top opportunities yet", subtitle: "Run AI extraction to score your saved jobs.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(opportunities)) { job in
                        OpportunityCard(job: job) {
                            router.selectedJobID = job.id
                            router.selectedSection = .jobs
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pipeline Funnel

    private var pipelineFunnelSection: some View {
        let stages: [(label: String, status: JobStatus)] = [
            ("Saved", .saved),
            ("Applied", .applied),
            ("Interview", .interview),
            ("Offer", .offer)
        ]
        let counts = stages.map { stage in
            (label: stage.label, status: stage.status, count: jobs.filter { $0.status == stage.status }.count)
        }

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Pipeline")

            GroupBox {
                Chart {
                    ForEach(counts, id: \.label) { item in
                        BarMark(
                            x: .value("Status", item.label),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(Theme.statusColor(item.status))
                        .cornerRadius(4)
                    }
                }
                .frame(height: 160)
                .chartXAxis(.automatic)
                .onTapGesture { } // handled per-bar below
            }

            // Tappable label row for navigation
            HStack(spacing: 0) {
                ForEach(counts, id: \.label) { item in
                    Button {
                        router.statusFilter = item.status.rawValue
                        router.selectedSection = .jobs
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(item.count)")
                                .font(.headline)
                                .foregroundStyle(Theme.statusColor(item.status))
                            Text(item.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
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
                    .frame(height: 120)
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
            .map { $0 }

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
        let issueJobs = jobs.filter { job in
            job.extractionStatus == .failed ||
            job.company == nil ||
            job.title == nil
        }

        return QualitySummarySection(issueCount: issueJobs.count)
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

// MARK: - OpportunityCard

private struct OpportunityCard: View {
    let job: Job
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.company ?? "Unknown Company")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text(job.title ?? "Unknown Title")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let score = job.fitScore {
                            VStack(spacing: 1) {
                                Text("\(score)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(fitScoreColor(score))
                                Text("fit")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    StatusChip(status: job.status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func fitScoreColor(_ score: Int) -> Color {
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .secondary
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
                            Button("Queue re-extraction") {
                                // Navigate to LLM Queue; re-extraction is triggered from there
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
