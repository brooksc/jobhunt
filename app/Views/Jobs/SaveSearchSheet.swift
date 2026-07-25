import JobhuntCore
import SwiftData
import SwiftUI

struct SaveSearchSheet: View {
    let filterState: JobsFilterState
    let searchText: String
    let searchTokens: [JobSearchToken]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var appServices
    @Query(sort: \SavedSearch.sortOrder) private var existing: [SavedSearch]

    @State private var name: String = ""
    @State private var saveError: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Search").font(.headline)

            TextField("e.g. Remote Staff+, Strong fit NYC", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { save() }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

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
        // Claim first responder once the sheet is on screen. This window hosts several coexisting
        // `.sheet` modifiers, which can leave a newly-presented sheet without a first responder so its
        // text field silently ignores typing (TASK-644 review).
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            fieldFocused = true
        }
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

    private var merged: JobsFilterState {
        var state = filterState
        state.searchText = searchText
        for token in searchTokens {
            switch token {
            case let .status(s):
                state.statusFilter = (state.statusFilter ?? []).union([s])
            case let .remoteType(rt):
                state.remoteFilter = (state.remoteFilter ?? []).union([rt])
            case let .minFitScore(n):
                state.minFitScore = max(state.minFitScore ?? 0, n)
            case let .minSalary(n):
                state.minSalary = max(state.minSalary ?? 0, n)
            case let .minRating(n):
                state.minRating = max(state.minRating ?? 0, n)
            case let .recentDays(d):
                state.recentDays = min(state.recentDays ?? Int.max, d)
            }
        }
        return state
    }

    private func buildChips() -> [String] {
        var out: [String] = []
        if let statuses = merged.statusFilter {
            out.append(statuses.map(\.displayName).sorted().joined(separator: ", "))
        }
        if let remotes = merged.remoteFilter {
            out.append(remotes.map { remoteLabel($0) }.sorted().joined(separator: ", "))
        }
        if !merged.searchText.isEmpty { out.append("\"\(merged.searchText)\"") }
        if let v = merged.minFitScore { out.append("Fit ≥ \(v)") }
        if let v = merged.minRating { out.append("Rating ≥ \(v)★") }
        if let v = merged.minSalary { out.append("Salary ≥ $\(v / 1000)k") }
        if let v = merged.recentDays { out.append("Last \(v) days") }
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
        let search = merged.toSavedSearch(name: trimmed, sortOrder: nextOrder)
        // Don't dismiss until the save actually persists, so a failure doesn't look successful.
        Task {
            do {
                try await appServices.jobService.insertSavedSearch(search)
                dismiss()
            } catch {
                saveError = "Couldn't save: \(error.localizedDescription)"
            }
        }
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
