import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Suggested companies

/// Offers the companies already in the library that nothing is watching (TASK-695, M6).
///
/// The leverage this exists for: a user who captured one posting at a company can turn that into a
/// source watching its entire board, forever, without knowing what an ATS is. Measured against real
/// boards, one captured Databricks posting becomes 821 roles under continuous watch.
///
/// Most suggestions cost no network request at all — the job's own URL already names the vendor and
/// the board. Only companies whose postings came from a careers page jobhunt can't read need
/// probing, and that is deliberately bounded.
struct SuggestedCompaniesSheet: View {
    let onAdd: (_ kind: String, _ label: String, _ slug: String, _ intervalHours: Int) -> Void
    @Environment(AppServices.self) private var appServices
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [CompanySuggestion] = []
    @State private var added: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Companies you're not watching").font(.headline)
            Text("You have jobs from these companies but nothing is checking their boards.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking through your jobs…").foregroundStyle(.secondary)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if suggestions.isEmpty {
                Text("Nothing to suggest — every company in your library is already watched, or "
                    + "their boards couldn't be identified.")
                    .foregroundStyle(.secondary)
            } else {
                List(suggestions) { suggestion in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.company).fontWeight(.medium)
                            Text(detail(for: suggestion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if added.contains(suggestion.id) {
                            Label("Added", systemImage: "checkmark").foregroundStyle(.green)
                        } else {
                            Button("Watch") {
                                onAdd(suggestion.board.kind, suggestion.company, suggestion.board.slug, 12)
                                added.insert(suggestion.id)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 220)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            suggestions = await CompanyDiscovery(store: appServices.backgroundStore).suggestions()
            isLoading = false
        }
    }

    /// The open-role count is only known for a board that was probed; a board read straight off a
    /// job's URL was never fetched, so it says nothing rather than claiming zero.
    private func detail(for suggestion: CompanySuggestion) -> String {
        var parts = [suggestion.board.displayName]
        if suggestion.board.jobCount > 0 {
            parts.append("\(suggestion.board.jobCount) open roles")
        }
        let saved = suggestion.existingJobCount
        parts.append("\(saved) job\(saved == 1 ? "" : "s") saved")
        return parts.joined(separator: " · ")
    }
}
