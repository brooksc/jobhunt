import SwiftData
import XCTest
@testable import JobhuntCore

final class AtomicTransitionTests: XCTestCase {
    private enum InjectedError: Error {
        case saveFailed
    }

    func testStatusTransition_saveFailureRollsBackStatusAndTimelineEvent() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1, status: .pursuing)
        try await store.insert(job)

        await store.setSaveFault(InjectedError.saveFailed)
        await XCTAssertThrowsErrorAsync {
            try await store.setJobStatus(.applied, jobIDs: [job.id])
        }
        await store.setSaveFault(nil)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let events = try await store.fetch(FetchDescriptor<JobEvent>())
        XCTAssertEqual(jobs.first?.status, .pursuing)
        XCTAssertTrue(events.isEmpty)
    }

    func testExtractionCommit_saveFailureRollsBackAllSuccessState() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1, extractionStatus: .running)
        try await store.insert(job)
        let request = LLMRequest(requestType: .extract, status: .running)
        request.job = job
        try await store.insert(request)

        let result = ExtractionResult(
            extractedJSON: "{\"title\":\"Engineer\"}",
            title: "Engineer",
            company: "Acme",
            location: nil,
            remoteType: nil,
            salaryMin: nil,
            salaryMax: nil,
            salaryHourlyMin: nil,
            salaryHourlyMax: nil,
            salaryCurrency: nil,
            salaryNote: nil,
            employmentType: nil,
            seniority: nil,
            applicationURL: nil,
            extractionConfidence: nil,
            extractionModel: "test-model",
            promptChars: 10,
            responseChars: 20,
            promptTokens: nil,
            completionTokens: nil,
            responseFormat: .text,
            meetsCriteria: true
        )
        let metadata = LLMCompletionMetadata(
            requestID: request.id,
            jobID: job.id,
            attempt: 1,
            modelRequested: "test-model",
            baseURL: "http://127.0.0.1:1234",
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            durationMs: 1000
        )

        await store.setSaveFault(InjectedError.saveFailed)
        await XCTAssertThrowsErrorAsync {
            _ = try await store.commitExtractionSuccess(result, metadata: metadata)
        }
        await store.setSaveFault(nil)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        let attempts = try await store.fetch(FetchDescriptor<LLMRequestAttempt>())
        let events = try await store.fetch(FetchDescriptor<JobEvent>())
        XCTAssertEqual(jobs.first?.extractionStatus, .running)
        XCTAssertNil(jobs.first?.extractedJSON)
        XCTAssertEqual(requests.first?.status, .running)
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertTrue(events.isEmpty)
    }

    func testFitCommit_saveFailureRollsBackScoreAttemptAndRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1)
        let resume = Resume(name: "General", text: "Swift engineer")
        try await store.insert(job)
        try await store.insert(resume)
        let request = LLMRequest(requestType: .fit, status: .running)
        request.job = job
        request.resume = resume
        try await store.insert(request)

        let score = FitScoreResult(
            overall: 80,
            breakdown: [:],
            penalty: 0,
            penaltyReasons: [],
            scoreWeights: [:]
        )
        let output = FitScoreOutput(
            score: score,
            fitScoreJSON: "{\"overall\":80}",
            promptChars: 10,
            responseChars: 20,
            promptTokens: nil,
            completionTokens: nil,
            modelReturned: "test-model",
            responseFormat: .text
        )
        let metadata = LLMCompletionMetadata(
            requestID: request.id,
            jobID: job.id,
            attempt: 1,
            modelRequested: "test-model",
            baseURL: "http://127.0.0.1:1234",
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            durationMs: 1000
        )

        await store.setSaveFault(InjectedError.saveFailed)
        await XCTAssertThrowsErrorAsync {
            _ = try await store.commitFitSuccess(
                output,
                fitJSON: output.fitScoreJSON,
                fitModel: "test-model",
                scoredAt: metadata.finishedAt,
                resumeID: resume.id,
                metadata: metadata
            )
        }
        await store.setSaveFault(nil)

        let scores = try await store.fetch(FetchDescriptor<JobFitScore>())
        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        let attempts = try await store.fetch(FetchDescriptor<LLMRequestAttempt>())
        XCTAssertTrue(scores.isEmpty)
        XCTAssertEqual(requests.first?.status, .running)
        XCTAssertTrue(attempts.isEmpty)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
