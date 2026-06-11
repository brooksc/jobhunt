import JobhuntCore
import SwiftUI

struct AddJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.jobService) private var jobService

    @State private var urlText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Job by URL").font(.headline)
            Text("Paste the URL of a job posting. The app will capture and extract the details automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("https://jobs.example.com/posting/12345", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }

            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
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
    }

    private func submit() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, URL(string: url) != nil else {
            errorMessage = "Please enter a valid URL."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let payload = CapturePayload(url: url, pageTitle: "", visibleText: "")
                _ = try await jobService?.ingestCapture(payload)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
