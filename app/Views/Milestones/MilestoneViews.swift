import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - MilestoneSection (TASK-501)

/// Structured interview + offer capture for the job detail. Before this, an interview date, the
/// interviewer, and the offer's compensation had nowhere to go but freeform notes — the most
/// consequential stage of the funnel was the only unstructured one.
///
/// Shown once a job reaches Interview/Offer (or whenever records already exist, so nothing becomes
/// unreachable if the status is later moved back).
struct MilestoneSection: View {
    let job: Job

    @Environment(AppServices.self) private var appServices
    @Query private var allInterviews: [InterviewRecord]
    @Query private var allOffers: [OfferRecord]

    @State private var editingInterview: InterviewTarget?
    @State private var editingOffer: OfferTarget?

    private struct InterviewTarget: Identifiable {
        let id: String
        let existing: InterviewRecord?
    }

    private struct OfferTarget: Identifiable {
        let id: String
        let existing: OfferRecord?
    }

    private var interviews: [InterviewRecord] {
        allInterviews.filter { $0.jobID == job.id }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var offer: OfferRecord? {
        allOffers.first { $0.jobID == job.id }
    }

    private var isApplicable: Bool {
        job.status == .interview || job.status == .offer || !interviews.isEmpty || offer != nil
    }

    var body: some View {
        if isApplicable { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Interviews & offer").font(.headline)
                Spacer()
                Button {
                    editingInterview = InterviewTarget(id: UUID().uuidString, existing: nil)
                } label: {
                    Label("Add interview", systemImage: "plus")
                }
                .controlSize(.small)
                .accessibilityIdentifier("milestone.addInterview")
                if offer == nil {
                    Button {
                        editingOffer = OfferTarget(id: UUID().uuidString, existing: nil)
                    } label: {
                        Label("Add offer", systemImage: "checkmark.seal")
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("milestone.addOffer")
                }
            }

            if interviews.isEmpty, offer == nil {
                Text("No interviews or offer recorded yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(interviews) { interview in
                interviewRow(interview)
                if interview.id != interviews.last?.id || offer != nil { Divider() }
            }
            if let offer { offerRow(offer) }
        }
        .sheet(item: $editingInterview) { target in
            InterviewEditor(
                jobID: job.id, existing: target.existing,
                onSave: { save($0) }, onCancel: { editingInterview = nil }
            )
        }
        .sheet(item: $editingOffer) { target in
            OfferEditor(
                jobID: job.id, existing: target.existing,
                onSave: { save($0) }, onCancel: { editingOffer = nil }
            )
        }
    }

    private func interviewRow(_ interview: InterviewRecord) -> some View {
        // Names the row's own interview: a column of identical pencils and trashes is unnavigable by
        // VoiceOver when every one of them is called "Edit" (TASK-700).
        let name = (InterviewKind(rawValue: interview.kind) ?? .other).label
            + " on " + interview.scheduledAt.formatted(date: .abbreviated, time: .shortened)
        return HStack(spacing: 8) {
            Image(systemName: "person.2").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text((InterviewKind(rawValue: interview.kind) ?? .other).label)
                    .font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(interview.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                    if let interviewer = interview.interviewer, !interviewer.isEmpty {
                        Text("· \(interviewer)").foregroundStyle(.tertiary)
                    }
                    if let location = interview.location, !location.isEmpty {
                        Text("· \(location)").foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .font(.caption2)
            }
            Spacer()
            Button { editingInterview = InterviewTarget(id: interview.id, existing: interview) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit interview: \(name)")
            .help("Edit this interview")
            Button { delete(interview) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove interview: \(name)")
                .help("Remove this interview")
        }
        .padding(.vertical, 5)
    }

    private func offerRow(_ offer: OfferRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal").foregroundStyle(.green).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(offer.title ?? "Offer").font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(offer.offeredAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                    if let base = offer.baseSalary {
                        Text("· \(base.formatted(.currency(code: "USD").precision(.fractionLength(0))))")
                            .foregroundStyle(.tertiary)
                    }
                    if let decisionBy = offer.decisionBy {
                        Text("· decide by \(decisionBy.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
            }
            Spacer()
            Button { editingOffer = OfferTarget(id: offer.id, existing: offer) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit offer: \(offer.title ?? "Offer")")
            .help("Edit the offer")
            Button { delete(offer) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove offer: \(offer.title ?? "Offer")")
                .help("Remove the offer")
        }
        .padding(.vertical, 5)
    }

    // MARK: - Actions

    private func save(_ input: InterviewInput) {
        Task {
            do {
                try await appServices.backgroundStore.recordInterview(input)
                editingInterview = nil // dismiss only once the write succeeds
            } catch {
                appServices.toastStore.show("Couldn't save interview: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func save(_ input: OfferInput) {
        Task {
            do {
                try await appServices.backgroundStore.recordOffer(input)
                editingOffer = nil
            } catch {
                appServices.toastStore.show("Couldn't save offer: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func delete(_ interview: InterviewRecord) {
        let id = interview.id
        Task {
            do { try await appServices.backgroundStore.deleteInterview(id: id) } catch {
                appServices.toastStore.show("Couldn't remove interview: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func delete(_ offer: OfferRecord) {
        let id = offer.id
        Task {
            do { try await appServices.backgroundStore.deleteOffer(id: id) } catch {
                appServices.toastStore.show("Couldn't remove offer: \(error.localizedDescription)", isError: true)
            }
        }
    }
}
