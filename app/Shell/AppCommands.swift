import SwiftUI

// MARK: - Job Commands
// Published by JobsView via .focusedSceneValue(\.jobCommands, ...) when the Jobs section is active.

struct JobCommandHandlers {
    let hasSelection: Bool
    let reEnqueueSelected: () -> Void
    let archiveSelected: () -> Void
}

private struct JobCommandsKey: FocusedValueKey {
    typealias Value = JobCommandHandlers
}

extension FocusedValues {
    var jobCommands: JobCommandHandlers? {
        get { self[JobCommandsKey.self] }
        set { self[JobCommandsKey.self] = newValue }
    }
}

struct JobMenuCommands: Commands {
    @FocusedValue(\.jobCommands) var handlers: JobCommandHandlers?

    var body: some Commands {
        CommandMenu("Jobs") {
            Button("Re-run AI Extraction") {
                handlers?.reEnqueueSelected()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(handlers?.hasSelection != true)

            Button("Archive Selected") {
                handlers?.archiveSelected()
            }
            .disabled(handlers?.hasSelection != true)
        }
    }
}

// MARK: - Queue Commands
// Published by LLMQueueView via .focusedSceneValue(\.queueCommands, ...) when Queue section is active.

struct QueueCommandHandlers {
    let isPaused: Bool
    let togglePause: () -> Void
}

private struct QueueCommandsKey: FocusedValueKey {
    typealias Value = QueueCommandHandlers
}

extension FocusedValues {
    var queueCommands: QueueCommandHandlers? {
        get { self[QueueCommandsKey.self] }
        set { self[QueueCommandsKey.self] = newValue }
    }
}

struct QueueMenuCommands: Commands {
    @FocusedValue(\.queueCommands) var handlers: QueueCommandHandlers?

    var body: some Commands {
        CommandMenu("Queue") {
            Button(handlers?.isPaused == true ? "Resume Queue" : "Pause Queue") {
                handlers?.togglePause()
            }
            .disabled(handlers == nil)
        }
    }
}

// MARK: - Quality Commands
// Published by DataQualityView via .focusedSceneValue(\.qualityCommands, ...) when Quality section is active.

struct QualityCommandHandlers {
    let hasSelection: Bool
    let markReviewed: () -> Void
    let queueReextraction: () -> Void
}

private struct QualityCommandsKey: FocusedValueKey {
    typealias Value = QualityCommandHandlers
}

extension FocusedValues {
    var qualityCommands: QualityCommandHandlers? {
        get { self[QualityCommandsKey.self] }
        set { self[QualityCommandsKey.self] = newValue }
    }
}

struct QualityMenuCommands: Commands {
    @FocusedValue(\.qualityCommands) var handlers: QualityCommandHandlers?

    var body: some Commands {
        CommandMenu("Data Quality") {
            Button("Mark Reviewed") {
                handlers?.markReviewed()
            }
            .disabled(handlers?.hasSelection != true)

            Button("Queue Re-extraction") {
                handlers?.queueReextraction()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(handlers?.hasSelection != true)
        }
    }
}
