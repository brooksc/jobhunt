import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - ReferralBadge (TASK-630)

/// A compact at-a-glance referral indicator for a job row / detail header (AC #8/#9). Renders nothing
/// for `.none`. Carries a tooltip + VoiceOver label with the state, latest recipient, and request date.
struct ReferralBadge: View {
    let summary: ReferralSummary
    var recipient: String?
    var lastDate: Date?

    var body: some View {
        if summary != .none {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.caption2)
                Text(summary.label).font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .help(detail)
            .accessibilityLabel("Referral: \(detail)")
        }
    }

    private var detail: String {
        var parts = [summary.label]
        if let recipient, !recipient.isEmpty { parts.append(recipient) }
        if let lastDate { parts.append(lastDate.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }

    private var symbol: String {
        switch summary {
        case .needsOutreach: "person.crop.circle.badge.exclamationmark"
        case .requested: "paperplane"
        case .responded: "bubble.left.and.bubble.right"
        case .submitted: "person.crop.circle.badge.checkmark"
        case .declined: "person.crop.circle.badge.xmark"
        case .notApplicable: "minus.circle"
        case .none: "circle"
        }
    }

    private var color: Color {
        switch summary {
        case .needsOutreach: .orange
        case .requested: .blue
        case .responded: .teal
        case .submitted: .green
        case .declined: .secondary
        case .notApplicable: .secondary
        case .none: .secondary
        }
    }
}

// MARK: - ReferralSection (job detail — AC #11)

/// The job-detail referral section: current summary, request history, and add/edit/remove actions,
/// plus an "N/A — no referral possible" toggle. Referral progress is orthogonal to the job's status.
struct ReferralSection: View {
    let job: Job

    @Environment(AppServices.self) private var appServices
    @Query private var allAttempts: [ReferralAttempt]

    @State private var editorAttempt: EditorTarget?

    /// Wraps an attempt (or a new one) for the `.sheet(item:)` editor.
    private struct EditorTarget: Identifiable {
        let id: String
        let existing: ReferralAttempt?
    }

    private var attempts: [ReferralAttempt] {
        allAttempts.filter { $0.jobID == job.id }.sorted { $0.requestedAt > $1.requestedAt }
    }

    private var realAttempts: [ReferralAttempt] {
        attempts.filter { $0.outcome != ReferralOutcome.notApplicable.rawValue }
    }

    private var isNotApplicable: Bool {
        attempts.contains { $0.outcome == ReferralOutcome.notApplicable.rawValue }
    }

    private var summary: ReferralSummary {
        ReferralTracking.summary(
            jobStatus: job.status.rawValue,
            attempts: attempts.map {
                .init(
                    outcome: ReferralOutcome(rawValue: $0.outcome) ?? .requested,
                    recipientName: $0.recipientName, recipientIdentifier: $0.recipientIdentifier,
                    requestedAt: $0.requestedAt
                )
            }
        )
    }

    /// Only show the section for jobs where referral outreach is meaningful — those in the active
    /// application funnel, or any job that already has recorded attempts (AC #2/#16).
    private var isApplicable: Bool {
        ReferralTracking.applicableStatuses.contains(job.status.rawValue) || !attempts.isEmpty
    }

    var body: some View {
        if isApplicable { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Referral").font(.headline)
                ReferralBadge(
                    summary: summary,
                    recipient: realAttempts.first?.recipientName,
                    lastDate: realAttempts.first?.requestedAt
                )
                Spacer()
                Button {
                    editorAttempt = EditorTarget(id: UUID().uuidString, existing: nil)
                } label: {
                    Label("Add outreach", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if realAttempts.isEmpty {
                Text(isNotApplicable
                    ? "Marked N/A — no referral possible for this job."
                    : "No referral request recorded yet.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(realAttempts) { attempt in
                        attemptRow(attempt)
                        if attempt.id != realAttempts.last?.id { Divider() }
                    }
                }
            }

            Toggle("N/A — no referral possible for this job", isOn: Binding(
                get: { isNotApplicable },
                set: { setNotApplicable($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            .disabled(!realAttempts.isEmpty) // a recorded request already means one is being pursued
        }
        .sheet(item: $editorAttempt) { target in
            ReferralAttemptEditor(
                jobID: job.id,
                existing: target.existing,
                priorAttempts: realAttempts,
                onSave: { input in save(input); editorAttempt = nil },
                onCancel: { editorAttempt = nil }
            )
        }
    }

    /// The date of the request's current state (Responded/Submitted/Declined date, else the ask date).
    private func stateDate(_ attempt: ReferralAttempt) -> Date {
        ReferralTracking.stateDate(
            outcome: ReferralOutcome(rawValue: attempt.outcome) ?? .requested,
            dates: .init(
                requested: attempt.requestedAt, responded: attempt.respondedAt,
                submitted: attempt.submittedAt, declined: attempt.declinedAt
            )
        )
    }

    private func attemptRow(_ attempt: ReferralAttempt) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(attempt.recipientName.isEmpty ? "(no recipient)" : attempt.recipientName)
                    .font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    let outcome = ReferralOutcome(rawValue: attempt.outcome) ?? .requested
                    Text(outcome.label).foregroundStyle(.secondary)
                    if let channel = attempt.channel, !channel.isEmpty {
                        Text("· \(channel)").foregroundStyle(.tertiary)
                    }
                    Text("· \(stateDate(attempt).formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2)
            }
            Spacer()
            Button { editorAttempt = EditorTarget(id: attempt.id, existing: attempt) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit this outreach")
            Button { delete(attempt) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this outreach")
        }
        .padding(.vertical, 5)
    }

    // MARK: - Actions

    private func save(_ input: ReferralAttemptInput) {
        Task {
            do { try await appServices.backgroundStore.recordReferralAttempt(input) } catch {
                appServices.toastStore.show("Couldn't save referral: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func delete(_ attempt: ReferralAttempt) {
        let id = attempt.id
        Task {
            do { try await appServices.backgroundStore.deleteReferralAttempt(id: id) } catch {
                appServices.toastStore.show("Couldn't remove referral: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func setNotApplicable(_ value: Bool) {
        Task {
            do { try await appServices.backgroundStore.setReferralNotApplicable(jobID: job.id, value) } catch {
                appServices.toastStore.show("Couldn't update: \(error.localizedDescription)", isError: true)
            }
        }
    }
}
