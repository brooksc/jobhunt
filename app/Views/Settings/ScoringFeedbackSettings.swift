import JobhuntCore
import SwiftUI

/// Split from SettingsTab.swift, which the addition pushed past the file-length limit.
extension JobsSettingsTab {
    // MARK: - Scoring feedback

    /// What the app has learned from corrections, shown so it can be inspected, edited and undone.
    ///
    /// A flag silently changing scoring forever is a mystery six weeks later when a number looks
    /// wrong. This is the same list the never-credit textbox would have been — except it's written
    /// by flagging assessments in place rather than authored up front.
    var scoringFeedbackSection: some View {
        Section("Scoring Corrections") {
            let entries = settings.scoringFeedback
            if entries.isEmpty {
                Text(
                    "None yet. When the AI gets a requirement wrong, right-click it in a job's Fit "
                        + "tab and choose “This assessment is wrong…”. Corrections are applied to "
                        + "every score, so you never have to make the same one twice."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(entries) { entry in
                    feedbackRow(entry)
                }
            }
        }
        .task(id: settings.scoringFeedback.count) { await refreshMatchCounts() }
        .sheet(item: $editingFeedback) { entry in
            ScoringFeedbackEditor(entry: entry) { updated in
                saveFeedbackEdit(updated)
            }
        }
    }

    private func feedbackRow(_ entry: ScoringFeedback) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // TASK-654 #2: the two kinds that move scores move them in OPPOSITE directions, so the
            // direction gets a colour and a glyph rather than living only inside the kind's wording.
            Image(systemName: polaritySymbol(entry.kind.polarity))
                .foregroundStyle(polarityColor(entry.kind.polarity))
                .help(entry.kind.explanation)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.phrase).font(.callout)
                Text(entry.kind.label).font(.caption).foregroundStyle(.secondary)
                provenanceLabel(entry)
                matchCountLabel(for: entry)
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            Button {
                editingFeedback = entry
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit this correction and rescore")

            Button {
                removeFeedback(entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this correction and rescore")
        }
    }

    /// TASK-654 #4: when it was made, and a way back to the job that motivated it.
    ///
    /// The age is the part that's easy to under-rate: after a résumé update an "I don't have this"
    /// from four months ago may simply no longer be true, and nothing else in the row hints at that.
    private func provenanceLabel(_ entry: ScoringFeedback) -> some View {
        HStack(spacing: 4) {
            Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
            if let number = entry.jobNumber {
                Text("·")
                // Settings is its own window, so this goes through the existing jobhunt://jobs/N
                // deep link rather than reaching for the main window's router.
                if let url = URL(string: "jobhunt://jobs/\(number)") {
                    Link("from #\(number)", destination: url)
                } else {
                    Text("from #\(number)")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func polaritySymbol(_ polarity: ScoringFeedback.Kind.Polarity) -> String {
        switch polarity {
        case .credits: "plus.circle.fill"
        case .penalises: "minus.circle.fill"
        case .neutral: "slash.circle.fill"
        }
    }

    private func polarityColor(_ polarity: ScoringFeedback.Kind.Polarity) -> Color {
        switch polarity {
        case .credits: .green
        case .penalises: .orange
        case .neutral: .secondary
        }
    }

    /// What a correction is actually doing right now — the two ways it goes wrong are both invisible
    /// otherwise. A rule matching nothing has been orphaned by a re-score rewording its requirement;
    /// one matching far more than its own job is over-broad.
    @ViewBuilder
    func matchCountLabel(for entry: ScoringFeedback) -> some View {
        if let count = feedbackMatchCounts[entry.id] {
            if count == 0 {
                Label(
                    "Matches nothing — the wording it was captured from has since changed",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text("Matches \(count) requirement\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    func refreshMatchCounts() async {
        await feedbackMatchCounts =
            (try? appServices.jobService.scoringFeedbackMatchCounts(settings.scoringFeedback)) ?? [:]
    }

    /// Editing re-derives scores exactly as removing does — a narrowed phrase that left the old
    /// scores in place would be worse than not editing at all (TASK-654 #5).
    func saveFeedbackEdit(_ updated: ScoringFeedback) {
        settings.updateScoringFeedback(updated)
        editingFeedback = nil
        Task {
            let count = try? await appServices.jobService.recomputeAllFitScores()
            appServices.toastStore.show("Correction updated — \(count ?? 0) score(s) updated")
            await refreshMatchCounts()
        }
    }

    /// Removing a correction re-derives the affected scores, so undo is as immediate as the flag was.
    func removeFeedback(_ id: String) {
        settings.removeScoringFeedback(id: id)
        Task {
            let updated = try? await appServices.jobService.recomputeAllFitScores()
            appServices.toastStore.show("Correction removed — \(updated ?? 0) score(s) updated")
            await refreshMatchCounts()
        }
    }
}

/// Edits a correction's phrase, kind and note, keeping its id, source job and creation date.
///
/// A separate sheet rather than inline fields: the phrase is the one field where a careless change
/// silently rescores the whole corpus, so it gets an explicit Save and a live rejection reason.
struct ScoringFeedbackEditor: View {
    let entry: ScoringFeedback
    let onSave: (ScoringFeedback) -> Void

    @State private var phrase: String
    @State private var kind: ScoringFeedback.Kind
    @State private var note: String
    @Environment(\.dismiss) private var dismiss

    init(entry: ScoringFeedback, onSave: @escaping (ScoringFeedback) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _phrase = State(initialValue: entry.phrase)
        _kind = State(initialValue: entry.kind)
        _note = State(initialValue: entry.note ?? "")
    }

    private var rejection: String? {
        ScoringFeedback.rejectionReason(forPhrase: phrase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Correction").font(.headline)

            Form {
                TextField("Phrase", text: $phrase)
                Picker("Correction", selection: $kind) {
                    ForEach(ScoringFeedback.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Note (optional)", text: $note)
            }

            Text(kind.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let rejection {
                Label(rejection, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(entry.updating(
                        phrase: phrase.trimmingCharacters(in: .whitespacesAndNewlines),
                        kind: kind,
                        note: note
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rejection != nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
