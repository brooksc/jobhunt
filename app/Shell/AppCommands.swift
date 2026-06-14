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
