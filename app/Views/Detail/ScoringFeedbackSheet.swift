import JobhuntCore
import SwiftUI

/// Captures a correction to a requirement assessment, at the moment the user sees it go wrong.
///
/// The phrase is editable and pre-filled with the requirement. SwiftUI exposes no way to read a text
/// selection — `.textSelection(.enabled)` permits copying but the selected string is not available to
/// the app — so "highlight the clause and flag it" can't be built directly. Editing a pre-filled
/// field reaches the same place: for a compound like "driving strategic programs and building a
/// remote-friendly culture" you trim it to the half that's wrong. Since compounds are now decomposed
/// at extraction, most rows arrive atomic and need no trimming at all.
struct ScoringFeedbackSheet: View {
    let requirement: String
    /// The assessment as it stands, used only to preselect the likely correction.
    let currentStatus: String
    let jobNumber: Int?
    let onSave: (ScoringFeedback) -> Void
    let onCancel: () -> Void
    /// Measures what the candidate phrase would hit. Injected rather than reached through the
    /// environment so the sheet stays previewable and testable.
    let measureReach: (String, ScoringFeedback.Kind, Int?) async -> FeedbackMatchPreview?

    @State private var phrase: String
    @State private var kind: ScoringFeedback.Kind
    @State private var note: String = ""
    @State private var reach: FeedbackMatchPreview?
    @State private var acknowledgedBroad = false

    init(
        requirement: String,
        currentStatus: String,
        jobNumber: Int?,
        onSave: @escaping (ScoringFeedback) -> Void,
        onCancel: @escaping () -> Void,
        measureReach: @escaping (String, ScoringFeedback.Kind, Int?) async -> FeedbackMatchPreview?
    ) {
        self.requirement = requirement
        self.currentStatus = currentStatus
        self.jobNumber = jobNumber
        self.onSave = onSave
        self.onCancel = onCancel
        self.measureReach = measureReach
        _phrase = State(initialValue: requirement)
        // Preselect the correction the row invites: a gap is usually flagged because the user does
        // have the thing, a tick because they can't defend it.
        _kind = State(initialValue: currentStatus == "met" ? .neverCredit : .alwaysCredit)
    }

    /// A phrase matching far more than intended is the main way this goes wrong. Reach is now
    /// **measured against the scored corpus** rather than guessed from the phrase's length: `IDE` is
    /// three characters and reached 30% of jobs, while `PCI DSS` is seven and hits only what it
    /// should. Length was never the signal.
    private var isBroad: Bool { reach?.isImplausiblyBroad ?? false }

    /// Phrases too short to identify anything are refused outright, not merely warned about.
    private var rejection: String? {
        ScoringFeedback.rejectionReason(forPhrase: phrase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Correct this requirement")
                .font(.headline)
            Text(requirement)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("What's wrong?").font(.caption.weight(.semibold))
                Picker("", selection: $kind) {
                    ForEach(ScoringFeedback.Kind.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                Text(kind.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if kind != .jobSpecific {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Match on").font(.caption.weight(.semibold))
                    TextField("phrase", text: $phrase, axis: .vertical)
                        .lineLimit(1 ... 3)
                    Text(
                        "Trim this to the part that's wrong. Narrower is safer — “electrical "
                            + "engineering” is a good rule, but “electrical” would also match "
                            + "“partner with electrical teams”."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if let rejection {
                        Label(rejection, systemImage: "exclamationmark.octagon")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let reach {
                        reachLabel(reach)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Note (optional)").font(.caption.weight(.semibold))
                TextField("why, for your own reference", text: $note, axis: .vertical)
                    .lineLimit(1 ... 3)
                // Deliberately not sent to the model: adding prose to the scoring prompt measurably
                // degraded it (job #231 regressed from 60 to 96 on one extra rule).
                Text("Kept for your reference — not sent to the AI.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                Spacer()
                Button("Save") {
                    onSave(ScoringFeedback(
                        phrase: kind == .jobSpecific ? requirement : phrase,
                        kind: kind,
                        jobNumber: jobNumber,
                        note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
                    ))
                }
                .buttonStyle(.borderedProminent)
                // A rule reaching a tenth of every scored job is a policy change, not a correction.
                // Require it to be acknowledged rather than blocking outright — occasionally the user
                // really does mean it.
                .disabled(kind != .jobSpecific && (rejection != nil || (isBroad && !acknowledgedBroad)))
            }
        }
        .padding(20)
        .frame(width: 460)
        .task(id: TaskKey(phrase: phrase, kind: kind)) {
            reach = nil
            acknowledgedBroad = false
            guard kind != .jobSpecific, ScoringFeedback.rejectionReason(forPhrase: phrase) == nil else { return }
            // Debounce: the corpus scan runs on every keystroke otherwise.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            reach = await measureReach(phrase, kind, jobNumber)
        }
    }

    /// Identifies a measurement request, so editing the phrase cancels the in-flight scan.
    private struct TaskKey: Equatable {
        let phrase: String
        let kind: ScoringFeedback.Kind
    }

    @ViewBuilder
    private func reachLabel(_ reach: FeedbackMatchPreview) -> some View {
        if reach.isImplausiblyBroad {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "This would change \(reach.matchingRequirements) requirements across "
                        + "\(reach.matchingJobs) of your \(reach.totalJobs) scored jobs.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                Toggle("Apply it that widely anyway", isOn: $acknowledgedBroad)
                    .font(.caption)
                    .toggleStyle(.checkbox)
            }
        } else {
            Text(
                reach.matchingRequirements == 0
                    ? "Matches nothing else you've scored yet."
                    : "Matches \(reach.matchingRequirements) requirement"
                    + (reach.matchingRequirements == 1 ? "" : "s")
                    + " across \(reach.matchingJobs) job"
                    + (reach.matchingJobs == 1 ? "." : "s.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
