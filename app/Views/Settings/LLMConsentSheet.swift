import JobhuntCore
import SwiftUI

struct LLMConsentSheet: View {
    let providerName: String
    let providerID: String
    let privacyURL: String?
    let settings: SettingsStore
    let onAgree: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Send data to \(providerName)?")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(
                "Job descriptions and resume data will be sent to \(providerName)'s servers for AI processing. " +
                    "This data may include job titles, company names, salary information, and your resume content."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if let urlString = privacyURL, let url = URL(string: urlString) {
                Link("View \(providerName) Privacy Policy", destination: url)
                    .font(.callout)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("I Agree") {
                    ConsentHelper.setConsent(provider: providerID, granted: true, settings: settings)
                    onAgree()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
