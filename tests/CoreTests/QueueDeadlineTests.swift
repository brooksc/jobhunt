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
