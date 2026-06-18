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

    private var overdueSites: [Site] {
        let now = Date()
        return sites.filter { site in
            guard site.state != .exclude, let next = site.nextReviewAt else { return false }
            return next < now
        }
    }

    private var dueSoonSites: [Site] {
        let now = Date()
        let sevenDays = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return sites.filter { site in
            guard site.state != .exclude, let next = site.nextReviewAt else { return false }
            return next >= now && next <= sevenDays
        }
    }

    private var reviewedSites: [Site] {
        let now = Date()
        let sevenDays = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return sites.filter { site in
            guard site.state == .reviewed else { return false }
            if let next = site.nextReviewAt {
                return next > sevenDays
            }
            return false
        }
    }

    private var notYetReviewedSites: [Site] {
        sites.filter { $0.state == .notReviewed && $0.nextReviewAt == nil }
    }

    private var excludedSites: [Site] {
        sites.filter { $0.state == .exclude }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(site.origin)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if let nextReview = site.nextReviewAt {
                    Text("·").font(.caption2).foregroundStyle(.quaternary)
                    nextReviewLabel(nextReview)
                } else if site.lastReviewedAt == nil {
                    Text("·").font(.caption2).foregroundStyle(.quaternary)
                    Text("Never reviewed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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
