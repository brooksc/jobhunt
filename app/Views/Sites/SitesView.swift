import JobhuntCore
import SwiftData
import SwiftUI

/// List pane for the Sites section. Displayed in ContentView's content column.
/// SiteDetailView is displayed in the detail column when router.selectedSiteID is set.
struct SitesView: View {
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices

    @Query(sort: \Site.nextReviewAt, order: .forward) private var sites: [Site]

    @State private var showAddSheet = false

    let siteService: SiteService

    // MARK: - Sections

    /// Shared bucket policy with the dashboard so the schedule, the card count, and these sections
    /// can't drift (TASK-582).
    private func sites(in bucket: SiteReviewBucket) -> [Site] {
        let now = Date()
        return sites.filter {
            SiteReviewBucket.classify(state: $0.state, nextReviewAt: $0.nextReviewAt, now: now) == bucket
        }
    }

    private var overdueSites: [Site] {
        sites(in: .overdue)
    }

    private var dueSoonSites: [Site] {
        sites(in: .dueSoon)
    }

    private var reviewedSites: [Site] {
        sites(in: .scheduledLater)
    }

    private var notYetReviewedSites: [Site] {
        sites(in: .notYetReviewed)
    }

    private var excludedSites: [Site] {
        sites(in: .excluded)
    }

    var body: some View {
        List(selection: Binding(
            get: { router.selectedSiteID },
            set: { router.selectedSiteID = $0 }
        )) {
            if sites.isEmpty {
                ContentUnavailableView(
                    "No Sites",
                    systemImage: "globe.slash",
                    description: Text("Add a site to start tracking job boards.")
                )
            } else {
                if !overdueSites.isEmpty {
                    Section("Overdue") {
                        ForEach(overdueSites) { site in
                            SiteRowView(site: site)
                                .tag(site.id)
                        }
                    }
                }

                if !dueSoonSites.isEmpty {
                    Section("Due Soon") {
                        ForEach(dueSoonSites) { site in
                            SiteRowView(site: site)
                                .tag(site.id)
                        }
                    }
                }

                if !reviewedSites.isEmpty {
                    Section("Reviewed") {
                        ForEach(reviewedSites) { site in
                            SiteRowView(site: site)
                                .tag(site.id)
                        }
                    }
                }

                if !notYetReviewedSites.isEmpty {
                    Section("Not Yet Reviewed") {
                        ForEach(notYetReviewedSites) { site in
                            SiteRowView(site: site)
                                .tag(site.id)
                        }
                    }
                }

                if !excludedSites.isEmpty {
                    Section("Excluded") {
                        ForEach(excludedSites) { site in
                            SiteRowView(site: site)
                                .tag(site.id)
                        }
                    }
                }
            }
        }
        // Match the Jobs list (inset/plain) rather than the gray source-list background.
        .listStyle(.inset)
        .navigationTitle("Sites")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Site", systemImage: "plus")
                }
                .help("Add a new job board site to track")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSiteSheet(siteService: siteService, intervalDays: appServices.settings.siteReviewIntervalDays)
        }
    }
}

// MARK: - Site Row

private struct SiteRowView: View {
    let site: Site

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(site.origin)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Review status, right-justified so the column lines up down the list.
            statusBadge
                .fixedSize()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let nextReview = site.nextReviewAt {
            nextReviewLabel(nextReview)
        } else if site.lastReviewedAt == nil {
            Text("Never reviewed")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var displayName: String {
        if let name = site.companyName, !name.isEmpty { return name }
        if !site.pageTitle.isEmpty { return site.pageTitle }
        return site.origin
    }

    @ViewBuilder
    private func nextReviewLabel(_ date: Date) -> some View {
        let diff = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if diff < 0 {
            Label("Overdue \(-diff)d", systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        } else if diff == 0 {
            Label("Due today", systemImage: "clock.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if diff <= 7 {
            Label("Due in \(diff)d", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else {
            Text(date, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
