import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// The queue used to stop dead and stay stopped (TASK-657).
///
/// A provider call that never returns kept its task alive forever. That task held the batch open, and
/// because `isRunning` stays true for as long as a drain is outstanding, every later start became a
/// silent no-op — the UI's "Resume" did nothing and only relaunching the app recovered. Two things
/// close that off: nothing may run unbounded, and a drain that has stopped making progress must be
/// supersedable.
final class QueueDeadlineTests: XCTestCase {
    private func makeQueue(store: BackgroundStore, timeout: Int) -> QueueActor {
        QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: {
                ExtractionSettings(
                    llmModel: "m", llmTimeout: timeout, preferredLocations: "",
                    locationFilterEnabled: false, locationAllowRemote: true,
                    locationAllowHybrid: true, locationAllowOnsite: true
                )
            },
            providerFactory: { LMStudioProvider() }
        )
    }

    private func makeStore() throws -> BackgroundStore {
        try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
    }

    // MARK: - The deadline

    /// The core guarantee: an operation that never finishes is cancelled rather than waited on.
    func testAnOperationThatNeverReturnsIsCancelled() async throws {
        let queue = try makeQueue(store: makeStore(), timeout: 1)
        let started = Date()

        do {
            _ = try await queue.withRequestDeadline(seconds: 0.4) {
                try await Task.sleep(for: .seconds(30))
                return true
            }
            XCTFail("expected the deadline to fire")
        } catch is LLMRequestTimeout {
            XCTAssertLessThan(
                Date().timeIntervalSince(started), 5,
                "the deadline must cut the call short, not wait for it"
            )
        }
    }

    /// A request that finishes inside its budget must be untouched — the deadline is a backstop, not
    /// a throttle.
    func testWorkInsideTheBudgetIsUnaffected() async throws {
        let queue = try makeQueue(store: makeStore(), timeout: 300)
        let value = try await queue.withRequestDeadline(seconds: 5) {
            try await Task.sleep(for: .milliseconds(20))
            return 42
        }
        XCTAssertEqual(value, 42)
    }

    /// The operation's own error must propagate unchanged, or a provider failure would be reported as
    /// a timeout and misclassified by the retry logic.
    func testTheOperationsOwnErrorIsNotMaskedByTheDeadline() async throws {
        struct ProviderBoom: Error {}
        let queue = try makeQueue(store: makeStore(), timeout: 300)
        do {
            _ = try await queue.withRequestDeadline(seconds: 5) { throw ProviderBoom() }
            XCTFail("expected the provider error")
        } catch is ProviderBoom {
            // expected
        } catch {
            XCTFail("deadline masked the real error with \(error)")
        }
    }

    /// Derived from the user's timeout setting rather than a second hidden knob, and generous enough
    /// that an ordinary slow request never trips it — measured requests ran 16–139s against the 300s
    /// default.
    func testDeadlineIsDerivedFromTheConfiguredTimeout() async throws {
        let queue = try makeQueue(store: makeStore(), timeout: 300)
        let deadline = await queue.requestDeadlineSeconds()
        XCTAssertGreaterThan(deadline, 300, "must exceed the transport timeout, not undercut it")
        XCTAssertLessThan(deadline, 1800)
    }

    /// A zero or unset timeout must not collapse the deadline to nothing, which would cancel every
    /// request immediately.
    func testAnUnsetTimeoutFallsBackToASaneDeadline() async throws {
        let queue = try makeQueue(store: makeStore(), timeout: 0)
        let deadline = await queue.requestDeadlineSeconds()
        XCTAssertGreaterThan(deadline, 60)
    }

    // MARK: - Stall recovery

    /// The stall threshold has to sit above the per-request deadline, or a legitimately slow request
    /// would be mistaken for a wedged drain and superseded mid-flight.
    func testStallThresholdIsAboveTheRequestDeadline() async throws {
        let queue = try makeQueue(store: makeStore(), timeout: 300)
        let deadline = await queue.requestDeadlineSeconds()
        XCTAssertGreaterThan(
            QueueActor.drainStallSeconds, deadline,
            "a slow-but-working request must not look like a stall"
        )
    }

    /// Starting a drain repeatedly must stay safe: the guard still prevents duplicate concurrent
    /// loops when the running drain is healthy.
    func testConcurrentStartsDoNotDuplicateTheDrain() async throws {
        let store = try makeStore()
        let queue = makeQueue(store: store, timeout: 300)
        async let a: Void = queue.startProcessing()
        async let b: Void = queue.startProcessing()
        async let c: Void = queue.startProcessing()
        _ = await (a, b, c)
        // Reaching here without hanging or crashing is the assertion: an empty queue drains and
        // clears `isRunning`, so a subsequent start is accepted rather than blocked forever.
        await queue.startProcessing()
    }
}

/// The orphan reaper (TASK-657, defects 1 and 2).
///
/// A row left in `running` mid-session sat there until the app restarted, and each one permanently
/// leaked a slot from the adaptive concurrency pool — several would throttle the queue toward serial
/// while presenting only as "the LLM queue is slow", with no error written anywhere.
final class QueueOrphanReaperTests: XCTestCase {
    private func makeQueue(store: BackgroundStore, timeout: Int = 10) -> QueueActor {
        QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: {
                ExtractionSettings(
                    llmModel: "m", llmTimeout: timeout, preferredLocations: "",
                    locationFilterEnabled: false, locationAllowRemote: true,
                    locationAllowHybrid: true, locationAllowOnsite: true
                )
            },
            providerFactory: { LMStudioProvider() }
        )
    }

    private func makeStore() throws -> (BackgroundStore, ModelContainer) {
        let container = try ModelContainerFactory.inMemory()
        return (BackgroundStore(modelContainer: container), container)
    }

    /// `startedAt` far enough back to exceed 2 × (llmTimeout × 1.5).
    private func insertRunning(_ container: ModelContainer, id: String, startedAgo: TimeInterval) throws {
        let ctx = ModelContext(container)
        let req = LLMRequest(id: id, requestType: .extract, status: .running)
        req.startedAt = Date(timeIntervalSinceNow: -startedAgo)
        ctx.insert(req)
        try ctx.save()
    }

    private func status(_ container: ModelContainer, _ id: String) throws -> LLMRequestStatus {
        let ctx = ModelContext(container)
        let req = try XCTUnwrap(
            ctx.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == id })).first
        )
        return req.status
    }

    /// #1 and #6: a stale `running` row goes back to `queued` with no user action.
    func testStaleRunningRowIsRequeued() async throws {
        let (store, container) = try makeStore()
        let queue = makeQueue(store: store, timeout: 10) // deadline 15s, reap bound 30s
        try insertRunning(container, id: "orphan", startedAgo: 600)

        let reaped = try await queue.reapOrphanedRunning()
        XCTAssertEqual(reaped, 1)
        XCTAssertEqual(try status(container, "orphan"), .queued)
    }

    /// #4: the orphan that prompted this left no evidence at all. Whatever else happens, the row now
    /// records why it was requeued.
    func testAReapedRowRecordsWhyItWasRequeued() async throws {
        let (store, container) = try makeStore()
        let queue = makeQueue(store: store)
        try insertRunning(container, id: "orphan", startedAgo: 600)

        _ = try await queue.reapOrphanedRunning()
        let ctx = ModelContext(container)
        let req = try XCTUnwrap(
            ctx.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == "orphan" })).first
        )
        XCTAssertNotNil(req.error)
        XCTAssertTrue(try XCTUnwrap(req.error).contains("Requeued automatically"))
        XCTAssertNil(req.startedAt, "a requeued row must not keep the start time of the attempt that died")
    }

    /// A request still inside its budget must not be snatched away mid-flight.
    func testAYoungRunningRowIsLeftAlone() async throws {
        let (store, container) = try makeStore()
        let queue = makeQueue(store: store, timeout: 300) // reap bound 900s
        try insertRunning(container, id: "working", startedAgo: 60)

        let reaped = try await queue.reapOrphanedRunning()
        XCTAssertEqual(reaped, 0)
        XCTAssertEqual(try status(container, "working"), .running)
    }

    /// #7: a cancellation that already reached a terminal status stays authoritative.
    func testTerminalRowsAreNeverResurrected() async throws {
        let (store, container) = try makeStore()
        let queue = makeQueue(store: store)
        let ctx = ModelContext(container)
        for (id, st) in [("done", LLMRequestStatus.succeeded), ("stopped", .cancelled), ("bad", .failed)] {
            let req = LLMRequest(id: id, requestType: .extract, status: st)
            req.startedAt = Date(timeIntervalSinceNow: -600)
            ctx.insert(req)
        }
        try ctx.save()

        let reaped = try await queue.reapOrphanedRunning()
        XCTAssertEqual(reaped, 0)
        XCTAssertEqual(try status(container, "done"), .succeeded)
        XCTAssertEqual(try status(container, "stopped"), .cancelled)
        XCTAssertEqual(try status(container, "bad"), .failed)
    }

    /// A row with no `startedAt` can't be aged, so it is left alone rather than guessed at.
    func testRunningRowWithNoStartTimeIsLeftAlone() async throws {
        let (store, container) = try makeStore()
        let queue = makeQueue(store: store)
        let ctx = ModelContext(container)
        ctx.insert(LLMRequest(id: "ageless", requestType: .extract, status: .running))
        try ctx.save()

        let reaped = try await queue.reapOrphanedRunning()
        XCTAssertEqual(reaped, 0)
        XCTAssertEqual(try status(container, "ageless"), .running)
    }

    /// #2: several orphans are all reclaimed in one pass, so leaked slots can't accumulate.
    func testEveryOrphanIsReclaimedInOnePass() async throws {
        let (store, container) = try makeStore()
        let queue = makeQueue(store: store)
        for i in 0 ..< 4 {
            try insertRunning(container, id: "orphan-\(i)", startedAgo: 600)
        }
        let reaped = try await queue.reapOrphanedRunning()
        XCTAssertEqual(reaped, 4)
        for i in 0 ..< 4 {
            XCTAssertEqual(try status(container, "orphan-\(i)"), .queued)
        }
    }
}

/// One request that never returns must not hold back the others (TASK-671).
///
/// The drain used to dispatch a batch and await the WHOLE group before fetching more, so free slots
/// idled until the batch's slowest member finished — measured 16s fastest against 139s slowest in a
/// single batch. With continuous dispatch a slot is refilled the moment it frees.
private final class OneHangsProvider: LLMProvider, @unchecked Sendable {
    let id = "one-hangs"
    let concurrencyLimit = 2
    private let lock = NSLock()
    private var seen = 0
    /// Ids of requests that were allowed to complete, in order.
    private(set) var completed: [Int] = []

    func complete(_: ChatRequest) async throws -> ChatResponse {
        let index: Int = lock.withLock {
            seen += 1
            return seen
        }
        if index == 1 {
            // Never returns on its own; only cancellation ends it.
            try await Task.sleep(nanoseconds: UInt64(3600) * 1_000_000_000)
        }
        lock.withLock { completed.append(index) }
        return ChatResponse(content: "{}", model: "stub", responseFormat: .text)
    }
}

final class QueueContinuousDispatchTests: XCTestCase {
    /// The concurrency limit is 2, so the hanging request occupies one slot for the whole test. Under
    /// the old barrier the drain awaited the entire batch, so the other slot served only the initial
    /// pair and then idled; with continuous dispatch it keeps taking new work.
    func testAHangingRequestDoesNotBlockTheRest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let provider = OneHangsProvider()

        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: {
                ExtractionSettings(
                    llmModel: "m", llmTimeout: 2, preferredLocations: "",
                    locationFilterEnabled: false, locationAllowRemote: true,
                    locationAllowHybrid: true, locationAllowOnsite: true
                )
            },
            providerFactory: { provider }
        )

        // Real jobs with captures, or processRequest skips them before ever reaching the provider —
        // the first version of this test "passed" with zero provider calls, so nothing hung and it
        // proved nothing.
        var jobIDs: [String] = []
        for idx in 0 ..< 5 {
            let capture = Capture(
                url: "https://example.com/job\(idx)",
                pageTitle: "Job \(idx)",
                selectedText: "Description \(idx).",
                rawHash: "cd-\(idx)"
            )
            let job = Job(jobNumber: idx + 1, title: "Job \(idx + 1)")
            job.capture = capture
            try await store.insert(job)
            jobIDs.append(job.id)
        }
        try await queue.enqueue(jobIDs: jobIDs, mode: .extract)

        let drain = Task { await queue.startProcessing() }
        try await Task.sleep(nanoseconds: 2_500_000_000)
        let reached = provider.completed.count
        drain.cancel()
        _ = await drain.value

        // Deliberately tight. With limit 2 the old barrier dispatches exactly the initial pair, so
        // ONE request completes and the rest wait for the hanging one — "at least 2" would have
        // passed under the very behaviour this guards against.
        XCTAssertGreaterThanOrEqual(
            reached, 3,
            "the free slot must keep taking new work while one request hangs (old barrier reached 1)"
        )
    }
}
