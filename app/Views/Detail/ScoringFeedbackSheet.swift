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
    let jobNumber: Int?
    let onSave: (ScoringFeedback) -> Void
    let onCancel: () -> Void

    @State private var phrase: String
    @State private var kind: ScoringFeedback.Kind = .neverCredit
    @State private var note: String = ""

    init(
        requirement: String,
        jobNumber: Int?,
        onSave: @escaping (ScoringFeedback) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.requirement = requirement
        self.jobNumber = jobNumber
        self.onSave = onSave
        self.onCancel = onCancel
        _phrase = State(initialValue: requirement)
    }

    /// A phrase matching far more than intended is the main way this goes wrong: "electrical" also
    /// fires on "partner with electrical teams". Warn rather than block — the user may mean it.
    private var isBroad: Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count < 5
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
                    if isBroad {
                        Label(
                            "That's very short — it may match requirements you didn't intend.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
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
                .disabled(phrase.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
