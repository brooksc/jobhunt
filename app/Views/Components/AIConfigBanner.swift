import JobhuntCore
import SwiftUI

/// Whether the AI provider is usable for extraction/fit scoring. Thin app-side alias over the core
/// `AIReadiness` rule (TASK-512) so the banner/service-status UI and the queue's provider gate can't
/// drift: a model is selected, and (for key-requiring providers) an API key is present.
enum AIConfig {
    static func isConfigured(_ settings: SettingsStore) -> Bool {
        AIReadiness.isConfigured(settings)
    }
}

/// A nudge shown on main screens when the AI provider isn't set up yet, deep-linking into the
/// ⌘, Settings window's LLM tab. AI config is essential (extraction + fit scoring) but lives in
/// Settings, so this makes the missing setup discoverable from where the user actually works.
struct AIConfigBanner: View {
    let settings: SettingsStore
    @Environment(Router.self) private var router
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !AIConfig.isConfigured(settings) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI provider not set up")
                        .font(.callout.weight(.semibold))
                    Text("Add an AI provider to enable automatic job extraction and résumé fit scoring.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Set Up AI…") {
                    router.settingsTab = .llm
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.3))
            )
        }
    }
}
