import JobhuntCore
import SwiftUI

/// The one thing jobhunt cannot guess and cannot work without (TASK-697).
///
/// Automatic search is on by default, but it is *interlocked* on this answer: with no title
/// keywords the gate matches every posting on every board, which would turn a 29,000-board sweep
/// into a day's worth of extractions on jobs the user never wanted. Asking here is what lets the
/// feature ship on rather than hidden behind a settings toggle a new user will never find.
struct JobTitlesStep: View {
    let settings: SettingsStore

    /// Deliberately concrete. "Enter job titles" produces one vague entry; a row of real examples
    /// produces the three or four specific ones the filter actually needs.
    private let suggestions = [
        "Product Manager", "Program Manager", "Software Engineer", "Data Analyst",
        "Designer", "Marketing Manager", "Account Executive", "Chief of Staff"
    ]

    private var current: [String] {
        DiscoverySettings.list(settings.string(forKey: SettingsKey.discoveryTitleInclude))
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("What are you looking for?")
                .font(.title2)
                .fontWeight(.semibold)

            Text("JobHunt checks thousands of company job boards for you. Tell it which titles "
                + "matter and it will only bring back those.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Job titles", text: Binding(
                    get: { settings.string(forKey: SettingsKey.discoveryTitleInclude) },
                    // Non-keychain key, so this write cannot fail — see SettingsStore.set.
                    set: { try? settings.set($0, forKey: SettingsKey.discoveryTitleInclude) }
                ), prompt: Text("Product Manager, Program Manager"))

                Section {
                    // Tapping beats typing for the common cases, and each tap demonstrates the
                    // comma-separated format better than a hint would.
                    FlowRow(items: suggestions) { suggestion in
                        Button(suggestion) { add(suggestion) }
                            .buttonStyle(.bordered)
                            .disabled(current.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame })
                    }
                } header: {
                    Text("Common titles").font(.caption)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 260)

            if current.isEmpty {
                Label(
                    "Without at least one title, automatic search stays off — it would otherwise "
                        + "match every job at every company.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
    }

    private func add(_ title: String) {
        var titles = current
        guard !titles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) else {
            return
        }
        titles.append(title)
        try? settings.set(titles.joined(separator: ", "), forKey: SettingsKey.discoveryTitleInclude)
    }
}

/// Wraps its items onto as many lines as they need. `LazyVGrid` can't do this — its columns are
/// fixed, and job titles vary from "Designer" to "Senior Technical Program Manager".
private struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { content($0) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Three per line: the suggestions are short enough that measuring text would be more machinery
    /// than the problem deserves.
    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0 ..< min($0 + 3, items.count)])
        }
    }
}
