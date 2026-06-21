import Foundation

/// Ordered restore boundary (TASK-546).
///
/// The SwiftData store is **single-writer**. Replacing its files while the LLM queue, availability
/// loop, or local HTTP server can still write risks WAL/state races and writes landing in the
/// moved-aside file after the swap is staged — the same hazard the docs call out for the external
/// migrator ("run with the app quit"). This coordinator enforces an equivalent in-app boundary:
///
///   1. **Quiesce** runtime writers first (cancel queue/availability tasks, stop the server).
///   2. **Safety-backup** the current (now quiesced) store.
///   3. **Replace** the store files.
///
/// so no background writer is active across the backup-and-replace window. The steps are injected as
/// closures, both to keep this in `JobhuntCore` (the quiesce is owned by the app's `AppServices`) and
/// so the ordering/failure behavior is unit-testable without the live app. Any throw aborts before
/// the destructive swap (or surfaces a swap failure) as a `StageError`; the caller reports the stage
/// and relaunches so the next launch opens a known store with a clean runtime.
@MainActor
public enum RestoreCoordinator {
    public enum Stage: Sendable, Equatable {
        case safetyBackup
        case restore
    }

    /// Identifies which step failed so the caller can show an accurate message.
    public struct StageError: Error {
        public let stage: Stage
        public let underlying: Error
    }

    public static func perform(
        backupURL: URL,
        storeURL: URL,
        safetyBackupURL: URL,
        quiesceRuntime: () async -> Void,
        backup: (_ storeURL: URL, _ dest: URL) throws -> Void = { try BackupService.backup(storeURL: $0, to: $1) },
        restore: (_ backupURL: URL, _ storeURL: URL) throws -> Void = { try BackupService.restore(from: $0, to: $1) }
    ) async throws {
        // 1. Stop background writers BEFORE touching any store files.
        await quiesceRuntime()
        // 2. Safety backup of the current store. If it fails, abort — never reach the destructive swap.
        do {
            try backup(storeURL, safetyBackupURL)
        } catch {
            throw StageError(stage: .safetyBackup, underlying: error)
        }
        // 3. Destructive swap.
        do {
            try restore(backupURL, storeURL)
        } catch {
            throw StageError(stage: .restore, underlying: error)
        }
    }
}
