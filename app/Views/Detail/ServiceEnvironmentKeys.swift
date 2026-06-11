import JobhuntCore
import SwiftUI

// Both keys are injected at ContentView via .environment(\.jobService, appServices.jobService)
// and .environment(\.queueActor, appServices.queueActor). New views should prefer
// @Environment(AppServices.self) directly; these keys exist for deep subviews in JobDetailView.

extension EnvironmentValues {
    @Entry var jobService: JobService?
}

extension EnvironmentValues {
    @Entry var queueActor: QueueActor?
}
