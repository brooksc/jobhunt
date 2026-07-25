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
                        // Editing the recipient invalidates a confirmation given for the *previous* one —
                        // otherwise confirming "Alice" then retyping "Bob" commits Bob unconfirmed (review #5).
                        .onChange(of: recipientName) { _, _ in showDuplicateConfirm = false }
                    TextField("LinkedIn URL or email (optional)", text: $identifier)
                        .onChange(of: identifier) { _, _ in showDuplicateConfirm = false }
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
                    ForEach(visibleFields, id: \.self) { field in
                        SheetDateField(
                            label: field.label,
                            date: binding(for: field),
                            lowerBound: lowerBound(for: field),
                            upperBound: upperBound(for: field)
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

    // MARK: - Timeline date fields

    /// The four timeline dates. An enum (not a raw string) so the switches below are exhaustive — a
    /// string-keyed lookup with a `default` arm silently routes a renamed row to the wrong date.
    private enum TimelineField: Hashable, CaseIterable {
        case requested, responded, submitted, declined

        var label: String {
            switch self {
            case .requested: "Requested"
            case .responded: "Responded"
            case .submitted: "Submitted"
            case .declined: "Declined"
            }
        }
    }

    /// The rows to show for the current status. Driven by `outcome` rather than by which dates happen to
    /// be non-nil, so reverting a status hides the later rows *without* discarding their dates — picking
    /// the status back up restores the original milestones instead of re-stamping today (review #8).
    private var visibleFields: [TimelineField] {
        var fields: [TimelineField] = [.requested]
        switch outcome {
        case .requested, .notApplicable:
            break
        case .responded:
            fields.append(.responded)
        case .submitted:
            if respondedAt != nil { fields.append(.responded) }
            fields.append(.submitted)
        case .declined:
            if respondedAt != nil { fields.append(.responded) }
            fields.append(.declined)
        }
        return fields
    }

    private func binding(for field: TimelineField) -> Binding<Date> {
        switch field {
        case .requested: Binding(get: { requestedAt }, set: { requestedAt = $0 })
        // The optional-backed rows are only visible once their date is set, so the fallback is unreachable.
        case .responded: Binding(get: { respondedAt ?? Date() }, set: { respondedAt = $0 })
        case .submitted: Binding(get: { submittedAt ?? Date() }, set: { submittedAt = $0 })
        case .declined: Binding(get: { declinedAt ?? Date() }, set: { declinedAt = $0 })
        }
    }

    /// Bounds keep the timeline in chronological order in *both* directions. Without an upper bound on
    /// Requested, moving the ask date forward past a later milestone persists an inverted timeline, which
    /// corrupts the follow-up staleness math and row sorting (review #1).
    private func lowerBound(for field: TimelineField) -> Date? {
        switch field {
        case .requested: nil
        case .responded: requestedAt
        case .submitted, .declined: respondedAt ?? requestedAt
        }
    }

    private func upperBound(for field: TimelineField) -> Date? {
        switch field {
        case .requested: [respondedAt, submittedAt, declinedAt].compactMap(\.self).min()
        case .responded: [submittedAt, declinedAt].compactMap(\.self).min()
        case .submitted, .declined: nil
        }
    }

    /// Stamp a newly-reached state's date. Dates for states that no longer apply are deliberately *not*
    /// cleared here — `performSave` normalizes them on the way to the store, so a mis-click in the Status
    /// picker is recoverable rather than destroying the original stamps.
    private func stampDate(for new: ReferralOutcome) {
        let now = Date()
        switch new {
        case .responded: if respondedAt == nil { respondedAt = now }
        case .submitted: if submittedAt == nil { submittedAt = now }
        case .declined: if declinedAt == nil { declinedAt = now }
        case .requested, .notApplicable: break
        }
    }

    private func attemptSave() {
        // A new request to an already-contacted recipient only ever *raises* the warning here; committing
        // requires the explicit "Record anyway" button. Letting Save commit on the second press meant a
        // double-Return (the field's Return fires the default button) blew straight past it (review #5).
        if existing == nil, duplicate != nil {
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
