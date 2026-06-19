import JobhuntCore
import SwiftUI

/// Whether the AI provider is usable for extraction/fit scoring: a model is selected, and (for
/// cloud providers) an API key is present. Local providers (LM Studio / loopback custom) need no key.
enum AIConfig {
    private static let cloudProviders: Set<String> = ["openai", "anthropic", "google", "openrouter"]

    static func isConfigured(_ settings: SettingsStore) -> Bool {
        let model = settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        if cloudProviders.contains(settings.llmProvider) {
            let key = settings.apiKey(forProvider: settings.llmProvider)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { return false }
        }
        return true
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
