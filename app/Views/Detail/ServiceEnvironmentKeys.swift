import SwiftUI
import JobhuntCore

// MARK: - JobService environment key

private struct JobServiceKey: EnvironmentKey {
    static let defaultValue: JobService? = nil
}

extension EnvironmentValues {
    var jobService: JobService? {
        get { self[JobServiceKey.self] }
        set { self[JobServiceKey.self] = newValue }
    }
}

// MARK: - QueueActor environment key

private struct QueueActorKey: EnvironmentKey {
    static let defaultValue: QueueActor? = nil
}

extension EnvironmentValues {
    var queueActor: QueueActor? {
        get { self[QueueActorKey.self] }
        set { self[QueueActorKey.self] = newValue }
    }
}
