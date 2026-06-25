import Foundation

/// Owns the lifecycle of an app's long-lived runtime tasks (e.g. the local server start, LLM-queue
/// crash recovery, the availability loop) so the start/shutdown invariants are unit-testable
/// independent of the full service graph (TASK-554/555/556).
///
/// - `start` is idempotent: a second call without an intervening `shutdown` is a no-op and does NOT
///   invoke the task factory, so it can't spawn duplicate loops (TASK-556).
/// - `shutdown` takes the task handles synchronously (before the first `await`), cancels them, then
///   AWAITS each one's exit before running `finalize` (e.g. stopping the server). Nothing the tasks
///   do can land after `shutdown` returns — the quiescing contract that termination (TASK-554) and
///   store-restore (TASK-546) depend on (TASK-555). Safe under repeated/concurrent calls: the
///   handles are cleared synchronously, so a second call awaits nothing.
///
/// Main-actor isolated because both ends run on the main actor in practice (start on the launch
/// path, shutdown from the termination/restore hooks), which removes the data race the previous
/// `@unchecked Sendable` task array relied on the author to avoid.
@MainActor
public final class RuntimeTaskController {
    private var tasks: [Task<Void, Never>] = []
    private var started = false

    public init() {}

    /// True between a successful `start` and the next `shutdown`.
    public var isStarted: Bool { started }

    /// Start the runtime tasks exactly once. If already started, returns `false` WITHOUT calling
    /// `makeTasks`; otherwise stores the tasks it produces and returns `true`.
    @discardableResult
    public func start(_ makeTasks: () -> [Task<Void, Never>]) -> Bool {
        guard !started else { return false }
        started = true
        tasks = makeTasks()
        return true
    }

    /// Cancel every task, await its exit, run `finalize`, then reset so a later `start` restarts
    /// cleanly. The handles are taken synchronously before any suspension point, so repeated or
    /// concurrent calls don't cancel/await the same set twice.
    public func shutdown(finalize: () async -> Void = {}) async {
        let current = tasks
        tasks = []
        started = false
        for task in current { task.cancel() }
        for task in current { await task.value }
        await finalize()
    }
}
