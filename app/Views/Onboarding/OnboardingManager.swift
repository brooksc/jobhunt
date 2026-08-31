import Foundation
import JobhuntCore
import Observation

@Observable
@MainActor
final class OnboardingManager {
    var isPresented: Bool
    var currentStep: Int = 0

    init(settings: SettingsStore) {
        isPresented = settings.string(forKey: "onboarding_complete") != "1"
    }

    func complete(settings: SettingsStore) {
        try? settings.set("1", forKey: "onboarding_complete")
        isPresented = false
    }

    /// Re-present the onboarding flow from the start (TASK-464: Settings → Debug "Reopen Onboarding").
    func reopen() {
        currentStep = 0
        isPresented = true
    }
}

extension Notification.Name {
    /// Posted by Settings → Debug to re-present onboarding (TASK-464).
    static let reopenOnboarding = Notification.Name("Jobhunt.reopenOnboarding")
}
