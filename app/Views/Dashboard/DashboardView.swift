import Charts
import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices

    /// All jobs — used for stat cards, opportunities, pipeline, quality
    @Query private var jobs: [Job]
    /// All captures in last 30 days — used for daily activity chart
    @Query private var recentCaptures: [Capture]
    /// Sites sorted by addedAt — filtered/sorted for schedule in computed property
    @Query(sort: \Site.addedAt) private var sites: [Site]
    /// LLM requests — used for the queue card in Housekeeping
    @Query private var llmRequests: [LLMRequest]
    /// Pending follow-up actions — drives the follow-ups recompute so it stays correct when an
    /// action is completed/snoozed without a `jobs` change.
    @Query(filter: #Predicate<JobAction> { $0.completedAt == nil }) private var pendingActions: [JobAction]
    /// Resolved duplicate decisions — feed the unresolved-pair count so it matches the Duplicates
    /// screen / sidebar badge (TASK-581).
    @Query private var duplicateDecisions: [DuplicateDecision]

    /// Cached aggregate metrics — recomputed only when `jobs` changes, not on every render.
    @State private var summary: JobStatusSummary = .zero
    /// Cached per-section derivations (TASK-363) — recomputed only when `jobs`/pending actions
    /// change, replacing repeated all-job scans in `body` computed properties.
    @State private var derived = DashboardDerived()

    /// Start-of-day token driving date-window metrics (TASK-583) — advances at local midnight (via
    /// `dayTick`) so date-window sections refresh across a day change with no data mutation.
    @State private var dayToken = Calendar.current.startOfDay(for: Date())
    private let dayTick = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

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
                SetupChecklistCard(settings: appServices.settings)
                statCardsSection
                TodayRecapCard(day: dayToken)
                // Above the funnel: a scheduled interview or an offer deadline outranks everything
                // else on this screen (TASK-646).
                DashboardMilestoneCard()
                HStack(alignment: .top, spacing: 16) {
                    pipelineFunnelSection
                    followUpsDueSection
                }
                DashboardReferralCard()
                HStack(alignment: .top, spacing: 16) {
                    recommendedToApplySection
                    recentCapturesSection
                }
                dailyActivitySection
                siteScheduleSection
                housekeepingSection
                qualitySummarySection
            }
            .padding(16)
        }
        .accessibilityIdentifier("content.dashboard")
        .navigationTitle("Dashboard")
        .onAppear { dayToken = Calendar.current.startOfDay(for: Date()); recomputeMetrics() }
        .onChange(of: jobs) { _, _ in recomputeMetrics() }
        // Follow-ups depend on action state, which can change without a `jobs` change.
        .onChange(of: pendingActions) { _, _ in recomputeMetrics() }
        // Resolving a duplicate (a new decision) can change the count without a `jobs` change.
        .onChange(of: duplicateDecisions) { _, _ in recomputeMetrics() }
        // TASK-583: day rollover — rebuild date-window metrics + re-render live-`Date()` sections.
        .onReceive(dayTick) { _ in
            let today = Calendar.current.startOfDay(for: Date())
            if today != dayToken { dayToken = today }
        }
        .onChange(of: dayToken) { _, _ in recomputeMetrics() }
    }

    // MARK: - Cached metrics (TASK-363)

    private func recomputeMetrics() {
        summary = JobStatusSummary(jobs: jobs)
        derived = DashboardDerived(jobs: jobs, decisions: duplicateDecisions, now: Date())
    }

    // MARK: - Stat Cards

    private var housekeepingSection: some View {
        let now = Date()
        let dupCount = derived.duplicateCount
        // Only sites actually past their scheduled review (overdue) — a brand-new site with no
        // review date is "not yet reviewed", not due, so it no longer inflates this card (TASK-582).
        let sitesDue = sites.count(where: {
            SiteReviewBucket.classify(state: $0.state, nextReviewAt: $0.nextReviewAt, now: now) == .overdue
        })
        let activeQueueCount = llmRequests.count(where: { $0.status == .queued || $0.status == .running })
        return VStack(alignment: .leading, spacing: 10) {
            Text("Housekeeping").font(.headline)
            HStack(spacing: 12) {
                housekeepingCard("Duplicates", count: dupCount, systemImage: "doc.on.doc") {
                    router.navigateToSection(.duplicates)
                }
                housekeepingCard("Sites due", count: sitesDue, systemImage: "globe") {
                    router.navigateToSection(.sites)
                }
                housekeepingCard("LLM queue", count: activeQueueCount, systemImage: "cpu") {
                    router.navigateToSection(.llmQueue)
                }
            }
        }
    }

    private func housekeepingCard(
        _ label: String,
        count: Int,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(count > 0 ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count)").font(.title3.weight(.semibold)).monospacedDigit()
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var statCardsSection: some View {
        HStack(spacing: 12) {
            StatCard(
                label: "Total Jobs",
                value: summary.total,
                systemImage: "briefcase",
                action: { showJobs(nil) }
            )
            StatCard(
                label: "Active",
                value: summary.active,
                systemImage: "flame",
                color: .blue,
                action: { showJobs(nil) }
            )
            StatCard(
                label: "Interviews",
                value: summary.interviews,
                systemImage: "person.2",
                color: .purple,
                action: { showJobs(.interview) }
            )
            StatCard(
                label: "Offers",
                value: summary.offers,
                systemImage: "star.fill",
                color: .green,
                action: { showJobs(.offer) }
            )
        }
    }

    /// Navigate to the Jobs list, optionally pre-filtered to a status smart folder.
    private func showJobs(_ status: JobStatus?) {
        router.activeSavedSearchID = nil
        router.sidebarJobFilter = status
        router.navigateToSection(.jobs)
    }

    // MARK: - Recommended to Apply

    private var recommendedToApplySection: some View {
        let recommended = derived.recommended

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
                                        Text(job.displayTitle)
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
        let recent = derived.recent

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
                                        Text(job.displayTitle)
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
        let dueSoon = derived.followUps

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
                                let action = job.actions
                                    .filter { FollowUpVisibility.isActionable($0, now: now) }
                                    .sorted { $0.dueDate < $1.dueDate }.first
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
                                        .frame(width: max(
                                            28,
                                            geo.size.width * CGFloat(item.count) / CGFloat(max(1, maxCount))
                                        ))
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

    private var siteScheduleSection: some View {
        let now = Date()
        let upcoming: [(site: Site, overdue: Bool)] = sites
            .compactMap { site -> (site: Site, overdue: Bool)? in
                // Shared bucket policy with the Sites screen (TASK-582): only scheduled sites appear
                // here; not-yet-reviewed and excluded sites are omitted.
                switch SiteReviewBucket.classify(state: site.state, nextReviewAt: site.nextReviewAt, now: now) {
                case .overdue: return (site: site, overdue: true)
                case .dueSoon, .scheduledLater: return (site: site, overdue: false)
                case .notYetReviewed, .excluded: return nil
                }
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
        QualitySummarySection(issueCount: derived.qualityIssueCount)
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

// MARK: - DashboardDerived (TASK-363)

/// Cached, all-job-derived dashboard sections, computed once per data change instead of in `body`
/// computed properties on every render. Lists are pre-bounded to what each section shows (top 4).
private struct DashboardDerived {
    var recommended: [Job] = []
    var recent: [Job] = []
    var followUps: [Job] = []
    var duplicateCount: Int = 0
    var qualityIssueCount: Int = 0

    init() {}

    /// Normalized `company|title` key for matching the "same role" across separate captures/duplicates.
    /// Conservative — exact normalized match only (lowercased, trimmed); nil if either side is blank.
    private static func roleKey(company: String?, title: String?) -> String? {
        let company = (company ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (title ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !company.isEmpty, !title.isEmpty else { return nil }
        return "\(company)|\(title)"
    }

    init(jobs: [Job], decisions: [DuplicateDecision], now: Date) {
        // Roles already handled elsewhere — applied to, or closed out (passed/rejected/expired/etc.) —
        // keyed by normalized company+title. Used to suppress recommending a role you're already done
        // with when it exists as a separate capture/duplicate (TASK-623 follow-up: a rejected Reddit
        // role was still being recommended via its levels.fyi duplicate).
        let handledStatuses: Set<JobStatus> = [
            .applied, .interview, .offer, .rejected, .passed, .closed, .expired, .archived, .duplicate
        ]
        let handledRoleKeys = Set(jobs.compactMap { job in
            handledStatuses.contains(job.status) ? Self.roleKey(company: job.company, title: job.title) : nil
        })
        recommended = Array(
            jobs.filter {
                $0.status == .pursuing && $0.fitStatus == .succeeded && ($0.fitScore ?? 0) > 0
                    && !(Self.roleKey(company: $0.company, title: $0.title).map(handledRoleKeys.contains) ?? false)
            }
            .sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }
            .prefix(4)
        )

        recent = Array(
            jobs.sorted { ($0.capture?.capturedAt ?? $0.createdAt) > ($1.capture?.capturedAt ?? $1.createdAt) }
                .prefix(4)
        )

        let dueCutoff = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        func activeDue(_ job: Job) -> Date? {
            job.actions
                .filter { FollowUpVisibility.isActionable($0, now: now) }
                .map(\.dueDate).min()
        }
        followUps = Array(
            jobs
                .compactMap { job -> (job: Job, due: Date)? in
                    guard let due = activeDue(job), due <= dueCutoff else { return nil }
                    return (job, due)
                }
                .sorted { $0.due < $1.due }
                .prefix(4)
                .map(\.job)
        )

        // Unresolved review pairs — same count as the Duplicates screen / sidebar badge, so the card
        // never opens an empty review queue (TASK-581).
        duplicateCount = DuplicateDetector.unresolvedPairCount(jobs: jobs, decisions: decisions)
        // Match the Data Quality screen's default view so the card doesn't promise issues that vanish
        // on open: eligible status, not already reviewed, and actually has issues (TASK-580).
        qualityIssueCount = jobs.count(where: {
            DataQualityScope.isIncluded(status: $0.status, hasReview: $0.qualityReview != nil, showReviewed: false)
                && !QualityChecker.issues(for: $0).isEmpty
        })
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let label: String
    let value: Int
    let systemImage: String
    var color: Color = .secondary
    /// When set, the whole card becomes a button that navigates to the matching jobs list.
    var action: (() -> Void)?

    private var card: some View {
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

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
                .help("Show \(label)")
        } else {
            card
        }
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
                        Text("Jobs with quality issues")
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
