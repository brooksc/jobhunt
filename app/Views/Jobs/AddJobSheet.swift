import JobhuntCore
import SwiftData
import SwiftUI

struct AddJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var appServices
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var modelContext

    @State private var urlText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Job number this URL already belongs to, when the add deduped onto an existing job.
    @State private var duplicateOf: Int?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Job by URL").font(.headline)
            Text("Paste the URL of a job posting. The app will capture and extract the details automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("https://jobs.example.com/posting/12345", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onChange(of: urlText) { _, _ in duplicateOf = nil }
                .onSubmit { submit() }

            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            if let number = duplicateOf {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Already tracked as job #\(number).")
                    Button("Open it") { openExisting(number) }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button(isSaving ? "Adding…" : "Add Job") { submit() }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        // Claim first responder once the sheet is on screen. This window hosts several coexisting
        // `.sheet` modifiers, which can leave a newly-presented sheet without a first responder so its
        // text field silently ignores typing (TASK-644 review).
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            fieldFocused = true
        }
    }

    /// Jump to the job this URL already belongs to.
    private func openExisting(_ number: Int) {
        var descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == number })
        descriptor.fetchLimit = 1
        if let job = try? modelContext.fetch(descriptor).first {
            router.selectJob(id: job.id, jobStatus: job.status)
        }
        dismiss()
    }

    private func submit() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Client-side validation with the SAME rule the service enforces (TASK-561), so inputs like
        // "example.com/jobs" that URL(string:) accepts but ingestion rejects are caught here instead
        // of after a round trip. The service's validatedForIngestion stays the authoritative guard.
        guard (try? URLNormalizer.validatedForIngestion(url)) != nil else {
            errorMessage = "Enter a valid http or https web address."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let result = try await appServices.jobService.addJobByURL(url)
                // Ingestion dedupes by URL, so re-adding something already tracked quietly recaptures
                // the existing job. Swallowing that made a duplicate indistinguishable from a new job —
                // during bulk adding it looks like the job "moved" on its own. Say so instead.
                if result.isDuplicate {
                    duplicateOf = result.jobNumber
                    isSaving = false
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
