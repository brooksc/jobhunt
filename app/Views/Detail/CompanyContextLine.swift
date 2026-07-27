import JobhuntCore
import SwiftUI

// MARK: - CompanyContextLine

/// A single subtle line above the pay range: other roles still open at this company, and whether
/// they've rejected you before. Renders nothing when there's neither, so it stays invisible on the
/// ~93% of jobs where the company appears once.
///
/// Collapsed by default because it's context, not a call to action — but it expands in place to the
/// ranked alternatives, since "which of these should I go for?" can't be answered by a count alone.
struct CompanyContextLine: View {
    let company: String
    let context: CompanyContext.Result
    let onOpen: (String) -> Void

    @State private var expanded = false

    private var summary: String {
        var parts: [String] = []
        if !context.openRoles.isEmpty {
            let n = context.openRoles.count
            parts.append("\(n) other open role\(n == 1 ? "" : "s") at \(company)")
            if let best = context.bestFit { parts.append("best fit \(best)") }
        }
        if !context.rejectedRoles.isEmpty {
            let n = context.rejectedRoles.count
            parts.append(context.openRoles.isEmpty
                ? "Previously rejected at \(company)"
                : "rejected here before")
            if n > 1 { parts[parts.count - 1] += " (\(n))" }
        }
        return parts.joined(separator: " · ")
    }

    /// Amber only when there are alternatives to weigh. A past rejection alone stays grey — it's an
    /// FYI, and a warning colour would imply this application is a mistake.
    private var tint: Color {
        context.openRoles.isEmpty ? .secondary : .orange
    }

    var body: some View {
        if !context.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: context.openRoles.isEmpty ? "info.circle" : "building.2")
                        Text(summary)
                        if !context.openRoles.isEmpty {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(context.openRoles.isEmpty) // nothing to expand for a rejection-only line
                .accessibilityLabel(summary)

                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(context.openRoles.prefix(5)) { role in
                            roleRow(role)
                            if role.id != context.openRoles.prefix(5).last?.id { Divider() }
                        }
                        if context.openRoles.count > 5 {
                            Text("+\(context.openRoles.count - 5) more")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        }
    }

    private func roleRow(_ role: CompanyContext.Role) -> some View {
        Button { onOpen(role.jobID) } label: {
            HStack(spacing: 8) {
                Text(role.fitScore.map(String.init) ?? "—")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(role.fitScore == nil ? .tertiary : .secondary)
                    .frame(width: 26, alignment: .trailing)
                Text(role.title).font(.caption).lineLimit(1)
                Text(role.status.displayName).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(role.title), \(role.status.displayName)"
                + (role.fitScore.map { ", fit \($0)" } ?? ", not scored")
        )
    }
}
