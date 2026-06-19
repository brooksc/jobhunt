import SwiftUI

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

// MARK: - Job Commands

// Published by JobsView via .focusedSceneValue(\.jobCommands, ...) — present whenever the Jobs
// section is in the scene. Acts on the current Jobs selection (TASK-507).

struct JobCommandHandlers {
    let hasSelection: Bool
    let openPosting: () -> Void
    let markApplied: () -> Void
    let markInterested: () -> Void
    let reRunExtraction: () -> Void
    let archive: () -> Void
    let delete: () -> Void
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

    private var enabled: Bool {
        handlers?.hasSelection == true
    }

    var body: some Commands {
        CommandMenu("Job") {
            Button("Open Posting") { handlers?.openPosting() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!enabled)
            Divider()
            Button("Mark Applied") { handlers?.markApplied() }
                .disabled(!enabled)
            Button("Mark Interested") { handlers?.markInterested() }
                .disabled(!enabled)
            Button("Re-run Extraction") { handlers?.reRunExtraction() }
                .keyboardShortcut("r", modifiers: [.command, .control])
                .disabled(!enabled)
            Divider()
            Button("Archive") { handlers?.archive() }
                .keyboardShortcut("a", modifiers: [.command, .control])
                .disabled(!enabled)
            Button("Delete…") { handlers?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!enabled)
        }
    }
}
