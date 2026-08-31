import SwiftData
import XCTest
@testable import JobhuntCore

/// End-to-end workflow test that chains the real components — ingest → extract → dedup →
/// quality → fit — asserting persisted state at each stage. The LLM is the only stub
/// (deterministic canned responses); everything else is the production code path.
final class WorkflowEndToEndTests: XCTestCase {
    /// Returns a fixed response regardless of request — lets us drive the real engine deterministically.
    private struct StubProvider: LLMProvider {
        let id = "stub"
        let concurrencyLimit = 1
        let response: String
        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(content: response, model: request.model, responseFormat: .text)
        }
    }

    private func extractionJSON(title: String, company: String) -> String {
        """
        {"title":"\(title)","company":"\(company)","location":"Remote","remote_type":"remote",
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":["Swift"],"summary":"Build great things.",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":0.9}
        """
    }

    private let fitJSON = """
    {"overall":82,"summary":"Strong match.","requirements_met":["Swift"],"requirements_not_met":[],
     "dimensions":[{"name":"required_qualifications","score":85,"rationale":"Good"},
                   {"name":"preferred_qualifications","score":60,"rationale":"Good"},
                   {"name":"skills","score":82,"rationale":"Good"},
                   {"name":"experience_level","score":80,"rationale":"Good"},
                   {"name":"domain_fit","score":75,"rationale":"Good"}]}
    """

    private func settings() -> ExtractionSettings {
        ExtractionSettings(
            llmModel: "stub-model", preferredLocations: "", locationFilterEnabled: false,
            locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
        )
    }

    func testFullWorkflow_ingestExtractDedupQualityFit() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { self.settings() },
            providerFactory: { StubProvider(response: "") }
        )
        let svc = JobService(store: store, queue: queue)

        // ── Stage 1: INGEST — same role cross-posted on two hosts ────────────────
        let r1 = try await svc.ingestCapture(CapturePayload(
            url: "https://acme.com/jobs/staff-eng",
            pageTitle: "Staff Engineer",
            selectedText: nil,
            visibleText: "Acme is hiring a Staff Engineer to build distributed systems at scale."
        ))
        let r2 = try await svc.ingestCapture(CapturePayload(
            url: "https://boards.greenhouse.io/acme/jobs/55",
            pageTitle: "Staff Engineer",
            selectedText: nil,
            visibleText: "Acme is hiring a Staff Engineer — join the platform team building at scale."
        ))
        XCTAssertFalse(r1.isDuplicate)
        XCTAssertFalse(r2.isDuplicate)
        let ingested = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(ingested.count, 2)

        // ── Stage 2: EXTRACT — run the real engine, persist like QueueActor does ──
        let provider = StubProvider(response: extractionJSON(title: "Staff Engineer", company: "Acme"))
        for job in try await store.fetch(FetchDescriptor<Job>()) {
            let cap = try XCTUnwrap(job.capture)
            let snap = JobExtractionSnapshot(
                captureURL: cap.url, captureCanonicalURL: cap.canonicalURL,
                capturePageTitle: cap.pageTitle, captureCleanedDescription: cap.cleanedDescription,
                captureVisibleText: cap.visibleText, captureSelectedText: cap.selectedText
            )
            let result = try await ExtractionEngine.extract(snapshot: snap, provider: provider, settings: settings())
            let jid = job.id
            try await store.update(Job.self, predicate: #Predicate { $0.id == jid }) { j in
                j.title = result.title
                j.company = result.company
                j.location = result.location
                j.extractedJSON = result.extractedJSON
                j.extractionStatus = .succeeded
                j.extractedAt = Date()
            }
        }
        let extracted = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertTrue(extracted.allSatisfy { $0.extractionStatus == .succeeded })
        XCTAssertTrue(extracted.allSatisfy { $0.company == "Acme" && $0.title == "Staff Engineer" })

        // ── Stage 3: DEDUP — a fuzzy cross-post is a REVIEW candidate, NOT auto-marked (TASK-622) ──
        // The two postings share company + title but have different cleaned text and no shared ATS id,
        // so it's a heuristic (similar_hash) match — surfaced for the user to confirm, not auto-flagged.
        let marked = try await store.detectAndPersistDomainDuplicates()
        XCTAssertEqual(marked, 0, "a fuzzy cross-post is surfaced for review, not auto-flagged")
        let dupes = try await store.fetch(FetchDescriptor<Job>()).filter { $0.duplicateOfJobID != nil }
        XCTAssertEqual(dupes.count, 0)
        // It IS detected as a review pair, preferring the company domain over the ATS as canonical.
        let jobsForReview = try await store.fetch(FetchDescriptor<Job>())
        let reviewPairs = DuplicateDetector().duplicateGroups(
            snapshots: DuplicateDetector.reviewSnapshots(jobs: jobsForReview), resolvedHashes: []
        )
        XCTAssertEqual(reviewPairs.count, 1, "the greenhouse cross-post is a review candidate")
        XCTAssertEqual(reviewPairs.first?.kind, .similarHash)
        XCTAssertEqual(reviewPairs.first?.original.sourceURL, "https://acme.com/jobs/staff-eng")
        XCTAssertEqual(reviewPairs.first?.candidate.sourceURL, "https://boards.greenhouse.io/acme/jobs/55")
        let keptID = try XCTUnwrap(reviewPairs.first?.original.id) // the company-domain posting is canonical
        let kept = try XCTUnwrap(jobsForReview.first { $0.id == keptID })

        // ── Stage 4: QUALITY — a company-less job surfaces a quality issue ───────
        let badJob = Job(title: "Mystery role", extractionStatus: .succeeded) // company nil
        try await store.insert(badJob)
        let issues = QualityChecker.issues(for: badJob)
        XCTAssertTrue(issues.contains(.missingCompany), "expected missingCompany; got \(issues)")

        // ── Stage 5: FIT — score the kept job against a resume, persist mirror ───
        let resume = Resume(name: "Mine", text: "Senior Swift engineer, distributed systems, 8 years.")
        try await store.insert(resume)
        let fitOut = try await ExtractionEngine.scoreFit(
            job: JobFitSnapshot(
                title: kept.title,
                company: kept.company,
                seniority: nil,
                extractedJSON: kept.extractedJSON,
                extractionModel: nil
            ),
            resume: ResumeSnapshot(text: resume.text),
            model: "stub-model",
            provider: StubProvider(response: fitJSON),
            feedback: []
        )
        try await store.saveFitScore(
            jobID: keptID, resumeID: resume.id, overall: fitOut.score.overall,
            fitJSON: fitOut.fitScoreJSON, model: "stub-model", scoredAt: Date()
        )
        let afterFit = try await store.fetch(FetchDescriptor<Job>())
        let scored = try XCTUnwrap(afterFit.first { $0.id == keptID })
        XCTAssertEqual(scored.fitScore, fitOut.score.overall)
        XCTAssertGreaterThan(fitOut.score.overall, 0)
        let fitRecords = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(fitRecords.count, 1)
    }
}
