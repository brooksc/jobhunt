import JobhuntCore
import SwiftUI

struct AddSiteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let siteService: SiteService

    @State private var urlText = ""
    @State private var nameText = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Site")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/jobs", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Name (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Company name", text: $nameText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    addSite()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func addSite() {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        let name = nameText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }

        guard let parsed = URL(string: url), parsed.scheme == "http" || parsed.scheme == "https" else {
            errorMessage = "Please enter a valid http or https URL."
            return
        }

        isAdding = true
        errorMessage = nil

        Task {
            do {
                _ = try await siteService.createSite(
                    url: url,
                    name: name.isEmpty ? nil : name
                )
                await MainActor.run {
                    isAdding = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAdding = false
                }
            }
        }
    }
}
