import Foundation
import JobhuntCore
import Observation

@Observable
final class OnboardingManager {
    var isPresented: Bool
    var currentStep: Int = 0

    init(settings: SettingsStore) {
        isPresented = settings.string(forKey: "onboarding_complete") != "1"
    }

    func complete(settings: SettingsStore) {
        settings.set("1", forKey: "onboarding_complete")
        isPresented = false
    }
}
