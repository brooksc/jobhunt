import JobhuntCore
import SwiftUI

// MARK: - ReferralAttemptEditor (TASK-630, AC #4/#6/#7)

/// Add or edit one referral outreach attempt. Captures a recipient (name or label) + optional
/// identifier/channel/note/date/outcome, and warns — requiring deliberate confirmation — before
/// recording a second outreach to a recipient already contacted for this job.
struct ReferralAttemptEditor: View {
    let jobID: String
    let existing: ReferralAttempt?
    let priorAttempts: [ReferralAttempt]
    let onSave: (ReferralAttemptInput) -> Void
    let onCancel: () -> Void

    @State private var recipientName: String
    @State private var identifier: String
    @State private var channel: String
    @State private var note: String
    @State private var outcome: ReferralOutcome
    @State private var requestedAt: Date
    @State private var confirmingDuplicate = false

    init(
        jobID: String, existing: ReferralAttempt?, priorAttempts: [ReferralAttempt],
        initialNote: String = "", onSave: @escaping (ReferralAttemptInput) -> Void, onCancel: @escaping () -> Void
    ) {
        self.jobID = jobID
        self.existing = existing
        self.priorAttempts = priorAttempts
        self.onSave = onSave
        self.onCancel = onCancel
        _recipientName = State(initialValue: existing?.recipientName ?? "")
        _identifier = State(initialValue: existing?.recipientIdentifier ?? "")
        _channel = State(initialValue: existing?.channel ?? "")
        _note = State(initialValue: existing?.note ?? initialNote)
        _outcome = State(initialValue: ReferralOutcome(rawValue: existing?.outcome ?? "") ?? .requested)
        _requestedAt = State(initialValue: existing?.requestedAt ?? Date())
    }

    /// A prior attempt (other than the one being edited) to the same recipient (AC #6).
    private var duplicate: ReferralTracking.Attempt? {
        let others = priorAttempts
            .filter { $0.id != existing?.id }
            .map {
                ReferralTracking.Attempt(
                    outcome: ReferralOutcome(rawValue: $0.outcome) ?? .requested,
                    recipientName: $0.recipientName, recipientIdentifier: $0.recipientIdentifier,
                    requestedAt: $0.requestedAt
                )
            }
        return ReferralTracking.duplicateAttempt(name: recipientName, identifier: identifier, among: others)
    }

    private var canSave: Bool {
        !recipientName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existing == nil ? "Record referral outreach" : "Edit referral outreach").font(.headline)
                Spacer()
            }
            .padding()
            Divider()
            Form {
                Section {
                    TextField("Recipient name or label", text: $recipientName)
                    TextField("LinkedIn URL or email (optional)", text: $identifier)
                    TextField("Channel (LinkedIn, email, referral portal…)", text: $channel)
                    Picker("Status", selection: $outcome) {
                        Text("Requested").tag(ReferralOutcome.requested)
                        Text("Referred / forwarded").tag(ReferralOutcome.referred)
                        Text("Declined").tag(ReferralOutcome.declined)
                    }
                    DatePicker("Date", selection: $requestedAt, displayedComponents: .date)
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2 ... 4)
                }
                if let duplicate {
                    Section {
                        Label(
                            "You already recorded outreach to this recipient on "
                                + "\(duplicate.requestedAt.formatted(date: .abbreviated, time: .omitted)).",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") { attemptSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 460, height: 500)
        .confirmationDialog(
            "Record another outreach to this recipient?",
            isPresented: $confirmingDuplicate
        ) {
            Button("Record anyway") { performSave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You've already contacted this recipient for this job. Recording again is fine for a "
                + "follow-up or correction — just confirming it's intentional.")
        }
    }

    private func attemptSave() {
        // New attempt (not an edit) to an already-contacted recipient → confirm first (AC #7).
        if existing == nil, duplicate != nil {
            confirmingDuplicate = true
        } else {
            performSave()
        }
    }

    private func performSave() {
        onSave(ReferralAttemptInput(
            id: existing?.id, jobID: jobID, recipientName: recipientName.trimmingCharacters(in: .whitespaces),
            recipientIdentifier: identifier, channel: channel, note: note,
            requestedAt: requestedAt, outcome: outcome.rawValue
        ))
    }
}
