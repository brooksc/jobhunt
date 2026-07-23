import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - DashboardReferralCard (TASK-644 Phase 2)

/// Dashboard referral nudges: surfaces applied jobs with no referral request yet (one click opens Jobs
/// pre-filtered to needs-outreach) and stale requests worth a follow-up. Renders nothing when there's
/// neither — self-contained (owns its queries, navigates via the router), like `TodayRecapCard`.
struct DashboardReferralCard: View {
    @Environment(Router.self) private var router
    @Query private var jobs: [Job]
    @Query private var attempts: [ReferralAttempt]

    private var attemptsByJob: [String: [ReferralAttempt]] {
        Dictionary(grouping: attempts, by: \.jobID)
    }

    private func projected(_ jobID: String) -> [ReferralTracking.Attempt] {
        (attemptsByJob[jobID] ?? []).map {
            .init(
                outcome: ReferralOutcome(rawValue: $0.outcome) ?? .requested,
                recipientName: $0.recipientName, recipientIdentifier: $0.recipientIdentifier,
                requestedAt: $0.requestedAt, respondedAt: $0.respondedAt
            )
        }
    }

    /// Applied / in-funnel jobs with no referral request yet and not N/A — the "go ask" list.
    private var needsRequestCount: Int {
        jobs.count(where: {
            ReferralTracking.summary(jobStatus: $0.status.rawValue, attempts: projected($0.id)) == .needsOutreach
        })
    }

    /// Stale requests, most-overdue first (oldest `since`).
    private var followUps: [(job: Job, nudge: ReferralTracking.ReferralNudge)] {
        let now = Date()
        return jobs
            .compactMap { job in ReferralTracking.followUp(attempts: projected(job.id), now: now).map { (job, $0) } }
            .sorted { $0.nudge.since < $1.nudge.since }
    }

    var body: some View {
        let needs = needsRequestCount
        let dueList = Array(followUps.prefix(5))
        if needs > 0 || !dueList.isEmpty {
            card(needs: needs, dueList: dueList)
        }
    }

    private func card(needs: Int, dueList: [(job: Job, nudge: ReferralTracking.ReferralNudge)]) -> some View {
        let now = Date()
        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.badge.gearshape").font(.caption).foregroundStyle(.orange)
                    Text("Referrals").font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.bottom, 10)

                if needs > 0 {
                    Button {
                        router.focusReferralOutreach = true
                        router.selectedSection = .jobs
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange)
                            Text("\(needs) applied — no referral requested yet").font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 7).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if !dueList.isEmpty { Divider() }
                }

                ForEach(dueList, id: \.job.id) { entry in
                    Button {
                        router.selectedJobID = entry.job.id
                        router.selectedSection = .jobs
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.job.company ?? "Unknown")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(nudgeText(entry.nudge, now: now))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 7).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if entry.job.id != dueList.last?.job.id { Divider() }
                }
            }
            .padding(4)
        }
    }

    private func nudgeText(_ nudge: ReferralTracking.ReferralNudge, now: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: nudge.since, to: now).day ?? 0)
        switch nudge.kind {
        case .awaitingResponse: return "Requested \(days)d ago — no response, follow up?"
        case .awaitingSubmission: return "Responded \(days)d ago — awaiting submission"
        }
    }
}
