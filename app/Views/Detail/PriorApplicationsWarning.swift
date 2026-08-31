import JobhuntCore
import SwiftUI

// MARK: - PriorApplicationsWarning (TASK-615)

/// An informational banner shown on an Interested job when the user has already applied to other roles
/// at the same company — a safeguard against applying twice. Never blocks; each prior role links out.
struct PriorApplicationsWarning: View {
    let company: String
    let matches: [PriorApplications.Match]
    let onOpen: (String) -> Void

    private var repeats: [PriorApplications.Match] {
        matches.filter(\.likelyRepeat)
    }

    private var isRepeat: Bool {
        !repeats.isEmpty
    }

    var body: some View {
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(headline, systemImage: isRepeat ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isRepeat ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(matches.prefix(4)) { match in
                    Button { onOpen(match.jobID) } label: {
                        HStack(spacing: 6) {
                            if let number = match.jobNumber {
                                Text(JobNumberDisplay.label(number))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            Text(match.title ?? "Untitled").lineLimit(1)
                            Text("· \(StatusDisplay.label(forRawValue: match.currentStatus))")
                                .foregroundStyle(.secondary)
                            if let applied = match.appliedAt {
                                Text("· \(applied.formatted(date: .abbreviated, time: .omitted))")
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .font(.caption)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((isRepeat ? Color.orange : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var headline: String {
        if let match = repeats.first, let title = match.title {
            return "Possible repeat application — you already applied to \u{201C}\(title)\u{201D} at \(company)."
        }
        let count = matches.count
        return "You've applied to \(count) other role\(count == 1 ? "" : "s") at \(company)."
    }
}
