import SwiftData
import XCTest
@testable import JobhuntCore

/// The queue must apply the user's scoring corrections to jobs it scores (TASK-707).
///
/// It didn't: `scoreFit`'s `feedback:` parameter was defaulted and `QueueActor` omitted it, so every
/// "I don't have this" was ignored by every job scored afterwards — the correction only ever took
/// effect if something later recomputed that job from its stored JSON. Nothing failed; the feature
/// just quietly did nothing on incoming work.
final class QueueScoringFeedbackTests: XCTestCase {
    /// The model credits CUDA. The user has said they don't have it, so the queue must demote it.
    private static let fitResponse = """
    {
      "overall": 90,
      "summary": "Strong match.",
      "dimensions": [
        {"name": "required_qualifications", "score": 90, "weight": 0.45, "rationale": "Meets"},
        {"name": "skills", "score": 90, "weight": 0.15, "rationale": "Good"},
        {"name": "preferred_qualifications", "score": 90, "weight": 0.05, "rationale": "Good"},
        {"name": "experience_level", "score": 90, "weight": 0.20, "rationale": "Senior"},
        {"name": "domain_fit", "score": 90, "weight": 0.15, "rationale": "Same domain"}
      ],
      "requirement_assessments": [
        {"requirement": "CUDA kernel optimization", "kind": "required", "status": "met",
         "evidence": "Optimized CUDA kernels"}
      ]
    }
    """

    private struct StubFitProvider: LLMProvider {
        let id = "stub-fit"
        let concurrencyLimit = 1
        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(
                content: QueueScoringFeedbackTests.fitResponse,
                model: request.model,
                responseFormat: .jsonObject
            )
        }
    }

    private func settings() -> ExtractionSettings {
        ExtractionSettings(
            llmModel: "stub-model", preferredLocations: "", locationFilterEnabled: false,
            locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
        )
    }

    private func scoreOneJob(feedback: [ScoringFeedback]) async throws -> (score: Int?, json: String?) {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let resume = Resume(name: "Mine", text: "Product manager, ten years, platform teams.")
        try await store.insert(resume)
        let job = Job(jobNumber: 4242, title: "ML Platform Engineer")
        job.company = "Acme"
        try await store.insert(job)
        _ = try await store.enqueueFitForActiveResumes(jobID: job.id)

        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { self.settings() },
            providerFactory: { StubFitProvider() },
            readScoringFeedback: { feedback }
        )
        await queue.startProcessing()

        // Copied out as plain values: a SwiftData model handed back from the store actor is tied to
        // a context this helper is about to drop.
        let scores = try await store.fetch(FetchDescriptor<JobFitScore>())
        let record = try XCTUnwrap(scores.first)
        return (record.fitScore, record.fitScoreJSON)
    }

    private func penaltyReasons(_ json: String?) throws -> [String] {
        let data = try XCTUnwrap(json?.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (dict["penaltyReasons"] as? [String]) ?? []
    }

    /// The headline assertion: a correction recorded *before* the job was scored reaches the analysis
    /// the queue stores. Compared against the same posting scored with no corrections, so the
    /// difference can only have come from the feedback.
    ///
    /// Asserted on the recorded gap rather than on the total: the model credited the requirement, and
    /// the correction is what turns it into a stated gap. Whether that gap also moves the number is
    /// the penalty model's business — with a single requirement in play it rounds to zero — while what
    /// TASK-707 broke was the correction reaching the scorer at all.
    func testNewlyScoredJobReflectsAnExistingCorrection() async throws {
        let uncorrected = try await scoreOneJob(feedback: [])
        let corrected = try await scoreOneJob(
            feedback: [ScoringFeedback(phrase: "CUDA", kind: .neverCredit)]
        )

        XCTAssertEqual(
            try penaltyReasons(uncorrected.json), [],
            "with no corrections recorded, the model's 'met' stands"
        )
        XCTAssertEqual(
            try penaltyReasons(corrected.json), ["CUDA kernel optimization (required/missing)"],
            "'I don't have this' must demote the requirement on a newly scored job"
        )
    }
}
