import JobhuntCore
import SwiftUI

// MARK: - InterviewEditor (TASK-501)

/// Add or edit one interview round. Date entry uses the shared `SheetDateField`, and the sheet claims
/// first responder on appear — this window hosts several coexisting sheets, which can otherwise leave a
/// newly-presented one without a responder so its text fields ignore typing (TASK-644 review).
struct InterviewEditor: View {
    let jobID: String
    let existing: InterviewRecord?
    let onSave: (InterviewInput) -> Void
    let onCancel: () -> Void

    @State private var scheduledAt: Date
    @State private var kind: InterviewKind
    @State private var interviewer: String
    @State private var location: String
    @State private var note: String
    @State private var recordID: String
    @FocusState private var interviewerFocused: Bool

    init(
        jobID: String, existing: InterviewRecord?,
        onSave: @escaping (InterviewInput) -> Void, onCancel: @escaping () -> Void
    ) {
        self.jobID = jobID
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _scheduledAt = State(initialValue: existing?.scheduledAt ?? Date())
        _kind = State(initialValue: InterviewKind(rawValue: existing?.kind ?? "") ?? .screen)
        _interviewer = State(initialValue: existing?.interviewer ?? "")
        _location = State(initialValue: existing?.location ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _recordID = State(initialValue: existing?.id ?? UUID().uuidString)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existing == nil ? "Record interview" : "Edit interview").font(.headline)
                Spacer()
            }
            .padding()
            Divider()
            Form {
                Section {
                    Picker("Round", selection: $kind) {
                        ForEach(InterviewKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    SheetDateField(label: "Date", date: $scheduledAt)
                    DatePicker("Time", selection: $scheduledAt, displayedComponents: .hourAndMinute)
                    TextField("Interviewer (optional)", text: $interviewer)
                        .focused($interviewerFocused)
                        .accessibilityIdentifier("interview.interviewer")
                    TextField("Location / link (optional)", text: $location)
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2 ... 4)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("interview.save")
            }
            .padding()
        }
        .frame(width: 460, height: 470)
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            interviewerFocused = true
        }
    }

    private func save() {
        onSave(InterviewInput(
            id: recordID, jobID: jobID, scheduledAt: scheduledAt, kind: kind.rawValue,
            interviewer: interviewer, location: location, note: note
        ))
    }
}

// MARK: - OfferEditor (TASK-501)

/// Add or edit the job's offer. Base salary is a whole-currency integer (consistent with
/// `Job.salaryMin/Max`); anything else about the package goes in the free-text comp field.
struct OfferEditor: View {
    let jobID: String
    let existing: OfferRecord?
    let onSave: (OfferInput) -> Void
    let onCancel: () -> Void

    @State private var offeredAt: Date
    @State private var title: String
    @State private var baseSalary: String
    @State private var additionalComp: String
    @State private var decisionBy: Date
    @State private var hasDecisionDate: Bool
    @State private var note: String
    @State private var recordID: String
    @FocusState private var titleFocused: Bool

    init(
        jobID: String, existing: OfferRecord?,
        onSave: @escaping (OfferInput) -> Void, onCancel: @escaping () -> Void
    ) {
        self.jobID = jobID
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        let offered = existing?.offeredAt ?? Date()
        _offeredAt = State(initialValue: offered)
        _title = State(initialValue: existing?.title ?? "")
        _baseSalary = State(initialValue: existing?.baseSalary.map(String.init) ?? "")
        _additionalComp = State(initialValue: existing?.additionalComp ?? "")
        _decisionBy = State(initialValue: existing?.decisionBy ?? offered.addingTimeInterval(7 * 86400))
        _hasDecisionDate = State(initialValue: existing?.decisionBy != nil)
        _note = State(initialValue: existing?.note ?? "")
        _recordID = State(initialValue: existing?.id ?? UUID().uuidString)
    }

    /// Digits only — a salary typed as "$185,000" still reads as 185000, and garbage yields nil rather
    /// than a misleading zero.
    private var parsedSalary: Int? {
        let digits = baseSalary.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existing == nil ? "Record offer" : "Edit offer").font(.headline)
                Spacer()
            }
            .padding()
            Divider()
            Form {
                Section {
                    TextField("Title offered (optional)", text: $title)
                        .focused($titleFocused)
                        .accessibilityIdentifier("offer.title")
                    SheetDateField(label: "Offered", date: $offeredAt)
                    TextField("Base salary (optional)", text: $baseSalary)
                        .accessibilityIdentifier("offer.baseSalary")
                    TextField("Equity / bonus / sign-on (optional)", text: $additionalComp)
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2 ... 4)
                }
                Section("Decision") {
                    Toggle("Decision deadline", isOn: $hasDecisionDate).toggleStyle(.checkbox)
                    if hasDecisionDate {
                        // Can't be due before the offer exists.
                        SheetDateField(label: "Decide by", date: $decisionBy, lowerBound: offeredAt)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("offer.save")
            }
            .padding()
        }
        .frame(width: 460, height: 520)
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            titleFocused = true
        }
    }

    private func save() {
        onSave(OfferInput(
            id: recordID, jobID: jobID, offeredAt: offeredAt, title: title, baseSalary: parsedSalary,
            additionalComp: additionalComp, decisionBy: hasDecisionDate ? decisionBy : nil, note: note
        ))
    }
}
