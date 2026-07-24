import JobhuntCore
import SwiftUI

// MARK: - ReferralAttemptEditor (TASK-630/644, AC #4/#6/#7)

/// Add or edit one referral request. Captures a recipient (name or label) + optional identifier/
/// channel/note, and a lifecycle status (Requested → Responded → Submitted, or Declined) with a date
/// stamped for each state reached. Reverting to an earlier status drops the later dates. Warns —
/// requiring deliberate confirmation — before recording a second request to an already-contacted person.
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
    @State private var respondedAt: Date?
    @State private var submittedAt: Date?
    @State private var declinedAt: Date?
    /// A stable id for this record for the editor's whole lifetime, so re-saving (after a failure or a
    /// double Save) upserts one row rather than creating duplicates (TASK-644 review #7).
    @State private var attemptID: String
    /// Set when Save is pressed on a new request to an already-contacted recipient — reveals an inline
    /// "Record anyway" instead of a `.confirmationDialog`, which as a modal inside this sheet is
    /// unreliable and can break the sheet's input (TASK-644 review #2).
    @State private var showDuplicateConfirm = false
    /// Drives first-responder for the recipient field. Presenting this editor as one of several
    /// coexisting sheets on the job-detail window can leave the sheet without a first responder, so
    /// clicks/keystrokes are ignored; explicitly claiming focus on appear restores text entry.
    @FocusState private var recipientFocused: Bool

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
        _respondedAt = State(initialValue: existing?.respondedAt)
        _submittedAt = State(initialValue: existing?.submittedAt)
        _declinedAt = State(initialValue: existing?.declinedAt)
        _attemptID = State(initialValue: existing?.id ?? UUID().uuidString)
    }

    /// A prior request (other than the one being edited) to the same recipient (AC #6).
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
                Text(existing == nil ? "Record referral request" : "Edit referral request").font(.headline)
                Spacer()
            }
            .padding()
            Divider()
            Form {
                Section {
                    TextField("Recipient name or label", text: $recipientName)
                        .focused($recipientFocused)
                        .accessibilityIdentifier("referral.recipient")
                    TextField("LinkedIn URL or email (optional)", text: $identifier)
                    TextField("Channel (LinkedIn, email, referral portal…)", text: $channel)
                    Picker("Status", selection: $outcome) {
                        ForEach(ReferralOutcome.requestStates, id: \.self) { state in
                            Text(state.label).tag(state)
                        }
                    }
                    .onChange(of: outcome) { _, new in stampDate(for: new) }
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2 ... 4)
                }
                Section("Timeline") {
                    InlineDateField(label: "Requested", date: $requestedAt)
                    if respondedAt != nil {
                        InlineDateField(label: "Responded", date: dateBinding(\.respondedAt), lowerBound: requestedAt)
                    }
                    if submittedAt != nil {
                        InlineDateField(
                            label: "Submitted",
                            date: dateBinding(\.submittedAt),
                            lowerBound: respondedAt ?? requestedAt
                        )
                    }
                    if declinedAt != nil {
                        InlineDateField(
                            label: "Declined",
                            date: dateBinding(\.declinedAt),
                            lowerBound: respondedAt ?? requestedAt
                        )
                    }
                }
                if let duplicate {
                    Section {
                        Label(
                            "You already recorded a request to this recipient on "
                                + "\(duplicate.requestedAt.formatted(date: .abbreviated, time: .omitted)).",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption).foregroundStyle(.orange)
                        if showDuplicateConfirm {
                            Text("Recording again is fine for a follow-up or correction.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Record anyway", role: .destructive) { performSave() }
                        }
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
                    .accessibilityIdentifier("referral.save")
            }
            .padding()
        }
        .frame(width: 460, height: 540)
        // Claim first responder once the sheet is on screen. The short hop lets the presentation settle
        // first — focusing during the present transition is dropped when several sheets coexist.
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            recipientFocused = true
        }
    }

    private func dateBinding(_ keyPath: ReferenceWritableKeyPath<ReferralAttemptEditor, Date?>) -> Binding<Date> {
        // Optional-backed dates are only shown once set, so the fallback is never surfaced.
        Binding(get: { self[keyPath: keyPath] ?? Date() }, set: { self[keyPath: keyPath] = $0 })
    }

    /// Stamp the newly-reached state's date (if unset) and clear dates that no longer apply, mirroring
    /// `ReferralTracking.normalizedDates` so the visible timeline matches what will be saved.
    private func stampDate(for new: ReferralOutcome) {
        let dates = ReferralTracking.normalizedDates(
            outcome: new,
            dates: .init(requested: requestedAt, responded: respondedAt, submitted: submittedAt, declined: declinedAt),
            now: Date()
        )
        respondedAt = dates.responded
        submittedAt = dates.submitted
        declinedAt = dates.declined
    }

    private func attemptSave() {
        // A new request (not an edit) to an already-contacted recipient → reveal the inline "Record
        // anyway" confirmation first; a second Save (or that button) commits it (AC #7).
        if existing == nil, duplicate != nil, !showDuplicateConfirm {
            showDuplicateConfirm = true
        } else {
            performSave()
        }
    }

    private func performSave() {
        let dates = ReferralTracking.normalizedDates(
            outcome: outcome,
            dates: .init(requested: requestedAt, responded: respondedAt, submitted: submittedAt, declined: declinedAt),
            now: Date()
        )
        onSave(ReferralAttemptInput(
            id: attemptID, jobID: jobID, recipientName: recipientName.trimmingCharacters(in: .whitespaces),
            recipientIdentifier: identifier, channel: channel, note: note,
            requestedAt: dates.requested, respondedAt: dates.responded, submittedAt: dates.submitted,
            declinedAt: dates.declined, outcome: outcome.rawValue
        ))
    }
}
