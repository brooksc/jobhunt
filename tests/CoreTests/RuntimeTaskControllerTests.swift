import XCTest
@testable import JobhuntCore

/// Records an ordered sequence of events from concurrent tasks (Sendable-safe via actor isolation).
private actor EventLog {
    private(set) var events: [String] = []
    func record(_ event: String) {
        events.append(event)
    }
}

/// A one-shot flag a task can set only after it observes cancellation and exits.
private actor Flag {
    private(set) var value = false
    func set() {
        value = true
    }
}

/// Verifies the start/shutdown invariants for `RuntimeTaskController` (TASK-554/555/556).
@MainActor
final class RuntimeTaskControllerTests: XCTestCase {
    /// A task that spins until cancelled, then runs `onExit`. Deterministic — no timeouts/sleeps.
    private func cancellableTask(onExit: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            await onExit()
        }
    }

    /// TASK-556 #1/#3: duplicate start is a no-op (factory not re-run); restart after shutdown works.
    func testStartIsIdempotentAndRestartable() async {
        let controller = RuntimeTaskController()
        var makeCount = 0
        let factory: () -> [Task<Void, Never>] = {
            makeCount += 1
            return [self.cancellableTask {}]
        }

        XCTAssertTrue(controller.start(factory))
        XCTAssertTrue(controller.isStarted)

        XCTAssertFalse(controller.start(factory), "second start without shutdown must be a no-op")
        XCTAssertEqual(makeCount, 1, "duplicate start must not create new tasks")

        await controller.shutdown()
        XCTAssertFalse(controller.isStarted)

        XCTAssertTrue(controller.start(factory), "start after shutdown must restart")
        XCTAssertEqual(makeCount, 2)
        await controller.shutdown()
    }

    /// TASK-555 #1/#3: shutdown does not return before a cancelled task has observed cancellation
    /// and exited.
    func testShutdownAwaitsTaskExit() async {
        let controller = RuntimeTaskController()
        let flag = Flag()
        controller.start {
            [self.cancellableTask { await flag.set() }]
        }

        await controller.shutdown()

        let observed = await flag.value
        XCTAssertTrue(observed, "shutdown must await each task's exit after cancellation")
        XCTAssertFalse(controller.isStarted)
    }

    /// TASK-554 #2: the finalize step (e.g. server stop) runs only AFTER all runtime tasks have exited.
    func testFinalizeRunsAfterTasksExit() async {
        let controller = RuntimeTaskController()
        let log = EventLog()
        controller.start {
            [self.cancellableTask { await log.record("task-exit") }]
        }

        await controller.shutdown {
            await log.record("finalize")
        }

        let events = await log.events
        XCTAssertEqual(
            events,
            ["task-exit", "finalize"],
            "finalize (server stop) must run only after runtime tasks have exited"
        )
    }

    /// TASK-555 #2: repeated shutdown is safe — the second call awaits nothing and still runs finalize.
    func testRepeatedShutdownIsSafe() async {
        let controller = RuntimeTaskController()
        var finalizeCount = 0
        controller.start { [self.cancellableTask {}] }

        await controller.shutdown { finalizeCount += 1 }
        await controller.shutdown { finalizeCount += 1 } // no tasks left — must not hang or crash

        XCTAssertFalse(controller.isStarted)
        XCTAssertEqual(finalizeCount, 2)
    }
}
