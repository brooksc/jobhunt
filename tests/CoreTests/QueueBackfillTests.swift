import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for BackgroundStore.backfillRequestModels — recovering LLMRequest.model from attempt history
/// for older finished rows that never persisted it (fit requests in particular).
final class QueueBackfillTests: XCTestCase {
    private func makeQueue(_ store: BackgroundStore) -> QueueActor {
        QueueActor(
            store: store,
            isPaused: { true },
            onSetPaused: { _ in },
            readExtractionSettings: {
                ExtractionSettings(
                    llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                    locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
                )
            },
            providerFactory: { LMStudioProvider() }
        )
    }

    private func fetchModel(_ store: BackgroundStore, id: String) async throws -> String? {
        try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == id })).first?.model
    }

    func testBackfill_usesReturnedModelFromLatestAttempt() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let req = LLMRequest(requestType: .fit, status: .succeeded)
        req.finishedAt = Date()
        req.attempts = [
            LLMRequestAttempt(requestType: .fit, attempt: 1, status: .failed, modelRequested: "openai"),
            LLMRequestAttempt(
                requestType: .fit, attempt: 2, status: .succeeded,
                modelRequested: "openai", modelReturned: "gpt-4o"
            )
        ]
        let id = req.id
        try await store.insert(req)

        try await store.backfillRequestModels()

        let model = try await fetchModel(store, id: id)
        XCTAssertEqual(model, "gpt-4o")
    }

    func testBackfill_fallsBackToRequestedModel() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let req = LLMRequest(requestType: .fit, status: .succeeded)
        req.finishedAt = Date()
        // Historical fit attempts recorded only modelRequested (the provider id).
        req.attempts = [
            LLMRequestAttempt(requestType: .fit, attempt: 1, status: .succeeded, modelRequested: "google")
        ]
        let id = req.id
        try await store.insert(req)

        try await store.backfillRequestModels()

        let model = try await fetchModel(store, id: id)
        XCTAssertEqual(model, "google")
    }

    func testBackfill_doesNotOverwriteExistingModel() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let req = LLMRequest(requestType: .extract, status: .succeeded)
        req.finishedAt = Date()
        req.model = "already-set"
        req.attempts = [
            LLMRequestAttempt(
                requestType: .extract, attempt: 1, status: .succeeded,
                modelRequested: "openai", modelReturned: "gpt-4o"
            )
        ]
        let id = req.id
        try await store.insert(req)

        try await store.backfillRequestModels()

        let model = try await fetchModel(store, id: id)
        XCTAssertEqual(model, "already-set")
    }

    func testClearCompleted_removesTerminalKeepsActive() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let queued = LLMRequest(requestType: .extract, status: .queued)
        let running = LLMRequest(requestType: .fit, status: .running)
        running.startedAt = Date()
        let done = LLMRequest(requestType: .extract, status: .succeeded)
        done.finishedAt = Date()
        let cancelled = LLMRequest(requestType: .fit, status: .cancelled)
        cancelled.finishedAt = Date()
        let exhausted = LLMRequest(requestType: .extract, status: .retryExhausted)
        exhausted.finishedAt = Date()
        for req in [queued, running, done, cancelled, exhausted] {
            try await store.insert(req)
        }

        try await makeQueue(store).clearCompleted()

        let remaining = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(remaining.count, 2, "only queued + running should remain")
        XCTAssertTrue(
            remaining.allSatisfy { $0.status == .queued || $0.status == .running },
            "finished requests should be cleared"
        )
    }
}

/// TASK-597: when the AI provider isn't configured (e.g. a cleared API key), queued work must
/// re-surface the `.providerNotConfigured` notice on each new user-initiated enqueue — not just once
/// per episode — so the app's blocked-state banner reappears instead of the job sitting silently at
/// "Queued".
final class QueueNotConfiguredReEmitTests: XCTestCase {
    private actor Collector {
        private(set) var events: [QueueEvent] = []
        func append(_ event: QueueEvent) {
            events.append(event)
        }

        func notConfiguredCount() -> Int {
            events.reduce(0) { count, event in
                if case .providerNotConfigured = event { return count + 1 }
                return count
            }
        }
    }

    private func makeUnconfiguredQueue(_ store: BackgroundStore) -> QueueActor {
        QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: {
                ExtractionSettings(
                    llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                    locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
                )
            },
            providerFactory: { LMStudioProvider() },
            isProviderConfigured: { false } // simulate a missing/cleared API key
        )
    }

    /// Poll until `predicate` holds or the deadline passes — bounds the async drain without a fixed,
    /// flaky sleep.
    private func poll(timeoutMs: Int = 3000, _ predicate: @Sendable () async -> Bool) async {
        for _ in 0 ..< (timeoutMs / 20) {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testProviderNotConfigured_emitsAndReArmsPerEnqueue() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let queue = makeUnconfiguredQueue(store)

        let job1 = Job(title: "One", status: .new)
        let job2 = Job(title: "Two", status: .new)
        try await store.insert(job1)
        try await store.insert(job2)
        _ = try await store.insertRequests(jobIDs: [job1.id], mode: .extract)

        // Subscribe OUTSIDE the consumer task so registration (now synchronous) completes before any
        // emit — then the consumer just drains the buffered stream. Reads use `poll` to tolerate the
        // consumer lagging behind the emit; nothing is dropped (unbounded buffering).
        let stream = await queue.subscribe()
        let collector = Collector()
        let sub = Task { for await event in stream {
            await collector.append(event)
        } }
        defer { sub.cancel() }

        // First drain (awaited → deterministic): unconfigured + queued work → one notice.
        await queue.startProcessing()
        await poll { await collector.notConfiguredCount() >= 1 }
        let firstCount = await collector.notConfiguredCount()
        XCTAssertEqual(firstCount, 1, "unconfigured queue with work must emit the notice")

        // A NEW enqueue while still unconfigured must re-arm the debounce and re-emit — otherwise the
        // banner would never reappear and the job sits silent.
        try await queue.enqueue(jobIDs: [job2.id], mode: .extract)
        await poll { await collector.notConfiguredCount() >= 2 }
        let secondCount = await collector.notConfiguredCount()
        XCTAssertEqual(
            secondCount, 2,
            "each new enqueue while unconfigured should re-surface .providerNotConfigured"
        )
    }
}
