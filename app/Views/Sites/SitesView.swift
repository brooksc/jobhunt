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

    /// The reminder cadence, for the overdue explainer. Per-site intervals exist, but the sentence is
    /// about the section, so it quotes the default the sites were created with.
    private var intervalDays: Int {
        appServices.settings.siteReviewIntervalDays
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
                    Section {
                        ForEach(overdueSites) { site in
                            SiteRowView(site: site, siteService: siteService)
                                .tag(site.id)
                        }
                    } header: {
                        Text("Overdue")
                    } footer: {
                        // What "overdue" means and what to do about it. The screen is a scan log: you
                        // sweep a careers page, mark it swept, and get reminded when it's worth another
                        // look. Nothing said so, so a red "Overdue 6d" read as an error rather than a
                        // nudge (TASK-503 #1).
                        Text(
                            "You last swept these more than \(intervalDays) days ago. "
                                + "Marking one reviewed starts the clock again."
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                if !dueSoonSites.isEmpty {
                    Section("Due Soon") {
                        ForEach(dueSoonSites) { site in
                            SiteRowView(site: site, siteService: siteService)
                                .tag(site.id)
                        }
                    }
                }

                if !reviewedSites.isEmpty {
                    Section("Reviewed") {
                        ForEach(reviewedSites) { site in
                            SiteRowView(site: site, siteService: siteService)
                                .tag(site.id)
                        }
                    }
                }

                if !notYetReviewedSites.isEmpty {
                    Section("Not Yet Reviewed") {
                        ForEach(notYetReviewedSites) { site in
                            SiteRowView(site: site, siteService: siteService)
                                .tag(site.id)
                        }
                    }
                }

                if !excludedSites.isEmpty {
                    Section("Excluded") {
                        ForEach(excludedSites) { site in
                            SiteRowView(site: site, siteService: siteService)
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
    let siteService: SiteService

    @State private var isWorking = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(site.origin)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Review status, right-justified so the column lines up down the list.
            statusBadge
                .fixedSize()

            // Inline, because opening the detail pane to say "yes, I looked at this" is most of the
            // work of the interaction it's recording (TASK-503 #1).
            inlineAction
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var inlineAction: some View {
        if site.state == .exclude {
            // Excluding was a one-way door: nothing in the UI could undo it.
            Button {
                perform { try await siteService.setSiteState(siteID: site.id, state: .notReviewed) }
            } label: {
                Label("Re-enable", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(isWorking)
            .help("Start tracking this site again")
        } else {
            Button {
                perform { try await siteService.markReviewed(siteID: site.id) }
            } label: {
                Label("Mark Reviewed", systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(isWorking)
            .help("Mark swept — the next reminder is scheduled from now")
        }
    }

    /// Guards against a double-click enqueueing the work twice; failures are left to the row's own
    /// state, which simply doesn't change.
    private func perform(_ work: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            try? await work()
            isWorking = false
        }
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

    /// Colour on the icon, not the words.
    ///
    /// The whole label used to be red or orange at caption2 size — orange on the list background is
    /// about 2:1, which the accessibility audit flagged on every scheduled row (TASK-689). The icon
    /// still carries the urgency at a glance; the text has to be readable.
    private func statusLabel(_ text: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(.caption2)
    }

    @ViewBuilder
    private func nextReviewLabel(_ date: Date) -> some View {
        let diff = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if diff < 0 {
            statusLabel("Overdue \(-diff)d", systemImage: "exclamationmark.circle.fill", tint: .red)
        } else if diff == 0 {
            statusLabel("Due today", systemImage: "clock.fill", tint: .orange)
        } else if diff <= 7 {
            statusLabel("Due in \(diff)d", systemImage: "clock", tint: .orange)
        } else {
            Text(date, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
