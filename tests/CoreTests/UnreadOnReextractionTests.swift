import SwiftData
import XCTest
@testable import JobhuntCore

/// The blue "unread" dot means the USER hasn't seen this job. It was set unconditionally on every
/// successful extraction, so re-running extraction on a job the user had already opened marked it new
/// again — sixteen already-triaged rows lit up after one batch of re-runs, one of them last opened
/// three weeks earlier. A bulk re-extraction after a prompt change would flag hundreds.
final class UnreadOnReextractionTests: XCTestCase {
    private func makeResult(title: String) -> ExtractionResult {
        ExtractionResult(
            extractedJSON: "{\"title\":\"\(title)\"}",
            title: title, company: "Acme", location: nil, remoteType: nil,
            salaryMin: nil, salaryMax: nil, salaryHourlyMin: nil, salaryHourlyMax: nil,
            salaryCurrency: nil, salaryNote: nil, employmentType: nil, seniority: nil,
            applicationURL: nil, extractionConfidence: nil, extractionModel: "test-model",
            promptChars: 10, responseChars: 20, promptTokens: nil, completionTokens: nil,
            responseFormat: .text, meetsCriteria: true
        )
    }

    private func commit(
        _ store: BackgroundStore, job: Job, title: String
    ) async throws {
        let request = LLMRequest(requestType: .extract, status: .running)
        request.job = job
        try await store.insert(request)
        let metadata = LLMCompletionMetadata(
            requestID: request.id, jobID: job.id, attempt: 1,
            modelRequested: "test-model", baseURL: "http://127.0.0.1:1234",
            startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2),
            durationMs: 1000
        )
        _ = try await store.commitExtractionSuccess(makeResult(title: title), metadata: metadata)
    }

    private func fetchJob(_ store: BackgroundStore, id: String) async throws -> Job {
        let jobs = try await store.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == id })
        )
        return try XCTUnwrap(jobs.first)
    }

    /// A job the user has never opened is genuinely news.
    func testFirstExtractionMarksAnUnopenedJobUnread() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1, extractionStatus: .running)
        try await store.insert(job)

        try await commit(store, job: job, title: "Engineer")
        let updated = try await fetchJob(store, id: job.id)
        XCTAssertTrue(updated.unread, "a never-opened job's first extraction is news")
    }

    /// The regression: re-extracting a job the user has read must not mark it new again.
    func testReextractionDoesNotUnreadAJobTheUserHasOpened() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1, extractionStatus: .running)
        try await store.insert(job)

        try await commit(store, job: job, title: "Engineer")
        // The user opens it — this is what clears the dot in the app. Written through the store
        // directly so the test doesn't have to stand up a whole QueueActor to press one button.
        let openedID = job.id
        try await store.update(Job.self, predicate: #Predicate { $0.id == openedID }) { row in
            row.lastOpenedAt = Date()
            row.unread = false
        }
        let afterOpen = try await fetchJob(store, id: job.id)
        XCTAssertFalse(afterOpen.unread)
        XCTAssertNotNil(afterOpen.lastOpenedAt)

        // Re-extraction, exactly as `rerun_extraction` or a bulk re-run drives it.
        afterOpen.extractionStatus = .running
        try await commit(store, job: job, title: "Engineer II")

        let reextracted = try await fetchJob(store, id: job.id)
        XCTAssertEqual(reextracted.title, "Engineer II", "the new extraction still applies")
        XCTAssertFalse(
            reextracted.unread,
            "a job the user has already opened must not be marked new by a re-extraction"
        )
    }
}
