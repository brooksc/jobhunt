import JobhuntCore
import SwiftUI

/// Split from SettingsTab.swift, which the addition pushed past the file-length limit.
extension JobsSettingsTab {
    // MARK: - Scoring feedback

    /// What the app has learned from corrections, shown so it can be inspected and undone.
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
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.phrase).font(.callout)
                            Text(entry.kind.label
                                + (entry.jobNumber.map { " · from #\($0)" } ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            matchCountLabel(for: entry)
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button {
                            removeFeedback(entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this correction and rescore")
                    }
                }
            }
        }
        .task(id: settings.scoringFeedback.count) { await refreshMatchCounts() }
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
