import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for QueueActor.backfillRequestModels — recovering LLMRequest.model from attempt history
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
        let store = BackgroundStore(modelContainer: try ModelContainerFactory.inMemory())
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

        try await makeQueue(store).backfillRequestModels()

        let model = try await fetchModel(store, id: id)
        XCTAssertEqual(model, "gpt-4o")
    }

    func testBackfill_fallsBackToRequestedModel() async throws {
        let store = BackgroundStore(modelContainer: try ModelContainerFactory.inMemory())
        let req = LLMRequest(requestType: .fit, status: .succeeded)
        req.finishedAt = Date()
        // Historical fit attempts recorded only modelRequested (the provider id).
        req.attempts = [
            LLMRequestAttempt(requestType: .fit, attempt: 1, status: .succeeded, modelRequested: "google")
        ]
        let id = req.id
        try await store.insert(req)

        try await makeQueue(store).backfillRequestModels()

        let model = try await fetchModel(store, id: id)
        XCTAssertEqual(model, "google")
    }

    func testBackfill_doesNotOverwriteExistingModel() async throws {
        let store = BackgroundStore(modelContainer: try ModelContainerFactory.inMemory())
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

        try await makeQueue(store).backfillRequestModels()

        let model = try await fetchModel(store, id: id)
        XCTAssertEqual(model, "already-set")
    }
}
