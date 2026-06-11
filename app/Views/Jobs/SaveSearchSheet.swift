import JobhuntCore
import SwiftData
import SwiftUI

struct SaveSearchSheet: View {
    let filterState: JobsFilterState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedSearch.sortOrder) private var existing: [SavedSearch]

    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Search").font(.headline)

            TextField("e.g. Remote Staff+, Strong fit NYC", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }

            // Summary of active filters
            filterSummary

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }

    @ViewBuilder
    private var filterSummary: some View {
        let chips = buildChips()
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Filters to save")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowSummary(chips: chips)
            }
        }
    }

    private func buildChips() -> [String] {
        var out: [String] = []
        if let statuses = filterState.statusFilter {
            out.append(statuses.map(\.displayName).sorted().joined(separator: ", "))
        }
        if let remotes = filterState.remoteFilter {
            out.append(remotes.map { remoteLabel($0) }.sorted().joined(separator: ", "))
        }
        if !filterState.searchText.isEmpty { out.append("\"\(filterState.searchText)\"") }
        if let v = filterState.minFitScore { out.append("Fit ≥ \(v)") }
        if let v = filterState.minRating { out.append("Rating ≥ \(v)★") }
        if let v = filterState.minSalary { out.append("Salary ≥ $\(v / 1000)k") }
        if let v = filterState.recentDays { out.append("Last \(v) days") }
        return out
    }

    private func remoteLabel(_ rt: RemoteType) -> String {
        switch rt {
        case .remote: "Remote"
        case .hybrid: "Hybrid"
        case .onsite: "On-site"
        case .unknown: "Unknown"
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let search = filterState.toSavedSearch(name: trimmed, sortOrder: nextOrder)
        modelContext.insert(search)
        dismiss()
    }
}

private struct FlowSummary: View {
    let chips: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
    }
}
