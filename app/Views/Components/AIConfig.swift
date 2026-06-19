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

// The standalone AIConfigBanner was superseded by SetupChecklistCard (TASK-498), which folds the
// AI-provider gate into a unified first-run checklist alongside résumé + extension.
