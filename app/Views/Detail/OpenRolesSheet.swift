import JobhuntCore
import SwiftUI

/// The company's other open roles, from its Greenhouse board (TASK-634).
///
/// Ranked rather than listed: a large employer's board runs to a couple of hundred postings, and
/// unranked they bury the two or three that resemble what the user is pursuing — which is the only
/// reason to look at this from a job page instead of the careers site.
struct OpenRolesSheet: View {
    let jobID: String
    let companyName: String?

    @Environment(AppServices.self) private var appServices
    @Environment(\.dismiss) private var dismiss

    @State private var roles: [OpenRoleRelevance.Scored] = []
    @State private var isLoading = true
    @State private var similarOnly = true
    @State private var adding: Set<String> = []
    @State private var added: Set<String> = []

    private var visible: [OpenRoleRelevance.Scored] {
        similarOnly ? roles.filter(OpenRoleRelevance.isSimilar) : roles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Other open roles\(companyName.map { " at \($0)" } ?? "")")
                    .font(.headline)
                Spacer()
                if !roles.isEmpty {
                    Toggle("Similar only", isOn: $similarOnly)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the company's job board…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if roles.isEmpty {
                // Distinguish "nothing there" from "we couldn't tell": the service returns an empty
                // list for both, and claiming the company has no other openings would be wrong.
                Text("Couldn't read the company's board, or it has no other open roles.")
                    .foregroundStyle(.secondary)
            } else if visible.isEmpty {
                Text("No closely similar roles. Turn off “Similar only” to see all \(roles.count).")
                    .foregroundStyle(.secondary)
            } else {
                List(visible) { scored in
                    roleRow(scored)
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await load() }
    }

    private func roleRow(_ scored: OpenRoleRelevance.Scored) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scored.role.title).font(.callout)
                HStack(spacing: 6) {
                    if let location = scored.role.locationName {
                        Text(location)
                    }
                    if scored.sameLocation {
                        Text("· same location")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let url = URL(string: scored.role.absoluteURL) {
                Link("Open", destination: url).font(.caption)
            }
            if added.contains(scored.id) {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Add") { add(scored) }
                    .controlSize(.small)
                    .disabled(adding.contains(scored.id))
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        let scored = await appServices.jobService.openRolesAtSameCompany(jobID: jobID)
        await MainActor.run {
            roles = scored
            isLoading = false
        }
    }

    /// Adds through the ordinary URL ingestion path, which already applies the duplicate policy —
    /// re-adding a role the user captured months ago must not create a second job.
    private func add(_ scored: OpenRoleRelevance.Scored) {
        adding.insert(scored.id)
        let url = scored.role.absoluteURL
        Task {
            do {
                let result = try await appServices.jobService.addJobByURL(url)
                await MainActor.run {
                    added.insert(scored.id)
                    adding.remove(scored.id)
                    appServices.toastStore.show(
                        result.isDuplicate
                            ? "Already tracked as #\(result.jobNumber)"
                            : "Added as #\(result.jobNumber)"
                    )
                }
            } catch {
                await MainActor.run {
                    adding.remove(scored.id)
                    appServices.toastStore.show(
                        "Couldn't add: \(error.localizedDescription)", isError: true
                    )
                }
            }
        }
    }
}
