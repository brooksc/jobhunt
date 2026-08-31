import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - TASK-693: the board row's own location field

/// Discovery holds the ATS's structured location field (`DiscoveredPosting.locationRaw`) and used to
/// drop it at `DiscoverySweeper.ingest`. These tests pin the three things that fix depends on:
/// the value reaches the stored `Capture` and survives back out through `extractionSnapshot`; it
/// fills an EMPTY extracted location and never overwrites a non-empty one; and it changes the
/// extraction prompt only when it exists, so extension/MCP captures are untouched.
final class BoardLocationTests: XCTestCase {
    // MARK: - Prompt

    private func extractionUserPrompt(boardLocation: String?) -> String {
        PromptBuilder.buildExtractionPrompt(
            description: "Build amazing things.",
            url: "https://example.com/job",
            pageTitle: "Engineer",
            boardLocation: boardLocation
        )[1].content
    }

    func testExtensionShapedPromptIsUnchangedWhenThereIsNoBoardLocation() {
        let prompt = extractionUserPrompt(boardLocation: nil)
        XCTAssertFalse(
            prompt.contains("Board location field"),
            "a capture with no board row must not gain a board-location section"
        )
        // The section is spliced between the location-preference rules and the metadata block with
        // no separator of its own, so an absent board location has to leave the seam byte-identical
        // — not merely section-free but without a stray blank line either.
        XCTAssertTrue(
            prompt.contains("values present in the source.\n\nKnown metadata:"),
            "the join between the location rules and Known metadata must be exactly as it was"
        )
    }

    func testOmittingTheArgumentMatchesPassingNil() {
        let implicit = PromptBuilder.buildExtractionPrompt(
            description: "Build amazing things.", url: "https://example.com/job", pageTitle: "Engineer"
        )[1].content
        XCTAssertEqual(implicit, extractionUserPrompt(boardLocation: nil))
    }

    func testABlankBoardLocationIsTreatedAsAbsent() {
        XCTAssertEqual(extractionUserPrompt(boardLocation: "   \n"), extractionUserPrompt(boardLocation: nil))
    }

    func testDiscoveryPromptCarriesTheBoardLocationAsALabelledHint() {
        let prompt = extractionUserPrompt(boardLocation: "United States, San Mateo, CA")
        XCTAssertTrue(prompt.contains("Board location field"))
        XCTAssertTrue(prompt.contains("United States, San Mateo, CA"))
        // It must stay a hint the body can override, not an instruction to copy it blindly: the
        // measured harm case is a body-stated remote role whose board row names an office.
        XCTAssertTrue(prompt.contains("unless the body"))
        XCTAssertTrue(prompt.contains("Known metadata:"), "the rest of the prompt is unaffected")
    }

    // MARK: - Deterministic fill

    /// Returns a canned extraction body so `extract` reaches the fill.
    private struct StubProvider: LLMProvider {
        let id = "stub"
        let concurrencyLimit = 1
        let response: String
        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(content: response, model: request.model, responseFormat: .jsonObject)
        }
    }

    private func extractionJSON(location: String) -> String {
        """
        {"title":"Engineer","company":"Acme","location":\(location),"remote_type":"onsite",
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":null,
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
    }

    private func settings() -> ExtractionSettings {
        ExtractionSettings(
            llmModel: "stub-model", preferredLocations: "", locationFilterEnabled: false,
            locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
        )
    }

    private func snapshot(boardLocation: String?) -> JobExtractionSnapshot {
        JobExtractionSnapshot(
            captureURL: "https://example.com/job", captureCanonicalURL: nil,
            capturePageTitle: "Engineer", captureCleanedDescription: "Build amazing things.",
            captureVisibleText: nil, captureSelectedText: nil,
            captureBoardLocation: boardLocation
        )
    }

    private func extract(modelLocation: String, boardLocation: String?) async throws -> ExtractionResult {
        try await ExtractionEngine.extract(
            snapshot: snapshot(boardLocation: boardLocation),
            provider: StubProvider(response: extractionJSON(location: modelLocation)),
            settings: settings()
        )
    }

    /// Bucket A — 183 of 613 measured jobs, and the reason job #1524 (fit 90) was badged as failing
    /// the user's criteria with no location at all.
    func testAnEmptyExtractedLocationIsFilledFromTheBoard() async throws {
        let result = try await extract(modelLocation: "null", boardLocation: "United States, San Mateo, CA")
        XCTAssertEqual(result.location, "United States, San Mateo, CA")
        XCTAssertTrue(
            result.extractedJSON.contains("San Mateo"),
            "the fill has to land in extractedJSON too, or the detail view and fit prompt miss it"
        )
    }

    func testAWhitespaceOnlyExtractedLocationCountsAsEmpty() async throws {
        let result = try await extract(modelLocation: "\"  \"", boardLocation: "New York, NY")
        XCTAssertEqual(result.location, "New York, NY")
    }

    /// The board value is NOT uniformly better. Overwriting cost ~63 rows against 20 gains in the
    /// measured comparison, so a non-empty extracted location always wins — including against a
    /// board value that looks richer.
    func testANonEmptyExtractedLocationIsNeverOverwritten() async throws {
        let result = try await extract(
            modelLocation: "\"New York\"", boardLocation: "New York, New York, United States"
        )
        XCTAssertEqual(result.location, "New York")
    }

    func testAnExtractedRemoteLocationSurvivesABoardOfficeAddress() async throws {
        let result = try await extract(modelLocation: "\"Remote\"", boardLocation: "United States, San Mateo, CA")
        XCTAssertEqual(
            result.location, "Remote",
            "preferring the board here would flip a remote role to on-site and fail the arrangement gate"
        )
    }

    func testNoBoardLocationLeavesAnEmptyExtractionEmpty() async throws {
        let result = try await extract(modelLocation: "null", boardLocation: nil)
        XCTAssertNil(result.location)
    }

    // MARK: - Persistence round-trip

    private func ingestInput(
        boardLocation: String?, url: String = "https://boards.example.com/j/1"
    ) -> AtomicIngestInput {
        AtomicIngestInput(
            captureID: "cap-\(UUID().uuidString)", jobID: "job-\(UUID().uuidString)",
            url: url, canonicalURL: nil, pageTitle: "Engineer",
            selectedText: nil, visibleText: "Build amazing things.",
            cleanedDescription: "Build amazing things.", structuredDataJSON: nil, userNote: nil,
            rawHash: UUID().uuidString, cleanedHash: nil,
            discoveredBySourceID: boardLocation == nil ? nil : "greenhouse",
            boardLocation: boardLocation
        )
    }

    /// A payload-only fix would work at first ingest and then silently undo itself, because the
    /// extraction prompt is rebuilt from the STORED capture on every re-extraction.
    func testTheBoardLocationSurvivesOntoTheCaptureAndBackIntoTheSnapshot() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let input = ingestInput(boardLocation: "United States, San Mateo, CA")
        _ = try await store.insertCaptureAtomically(input)

        let captures = try await store.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.first?.boardLocation, "United States, San Mateo, CA")

        let snapshot = try await store.extractionSnapshot(forJobID: input.jobID)
        XCTAssertEqual(snapshot?.captureBoardLocation, "United States, San Mateo, CA")
    }

    func testANonDiscoveryIngestStoresNoBoardLocation() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let input = ingestInput(boardLocation: nil)
        _ = try await store.insertCaptureAtomically(input)

        let snapshot = try await store.extractionSnapshot(forJobID: input.jobID)
        XCTAssertNil(snapshot?.captureBoardLocation)
    }

    /// A browser recapture of a discovery-found posting carries no board row. Clearing the stored one
    /// there would lose it for good — the ledger row that produced it is transient.
    func testARecaptureWithoutABoardLocationKeepsTheStoredOne() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let url = "https://boards.example.com/j/1"
        let first = ingestInput(boardLocation: "United States, San Mateo, CA", url: url)
        _ = try await store.insertCaptureAtomically(first)

        // Same URL, different content, no board row — the extension recapture path.
        _ = try await store.insertCaptureAtomically(ingestInput(boardLocation: nil, url: url))

        let captures = try await store.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures.first?.boardLocation, "United States, San Mateo, CA")
    }

    // MARK: - The CapturePayload hop

    private struct NoOpProvider: LLMProvider {
        let id = "noop"
        let concurrencyLimit = 1
        func complete(_: ChatRequest) async throws -> ChatResponse {
            throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
        }
    }

    private func makeService(_ store: BackgroundStore) -> JobService {
        JobService(store: store, queue: QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { NoOpProvider() }
        ))
    }

    /// `DiscoverySweeper.ingest` is the one hop where `DiscoveredPosting.locationRaw` used to be
    /// dropped: it builds a `CapturePayload`, which had no field to put it in.
    func testACapturePayloadCarriesTheBoardLocationThroughToTheCapture() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let service = makeService(store)
        _ = try await service.ingestCapture(
            CapturePayload(
                url: "https://job-boards.greenhouse.io/sony/jobs/6011556004",
                pageTitle: "Senior Product Manager - Monetization",
                visibleText: "Own monetization strategy for our platform.",
                discoveredBySourceID: "greenhouse",
                boardLocation: "United States, San Mateo, CA"
            ),
            createOnly: true
        )
        let captures: [Capture] = try await store.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.first?.boardLocation, "United States, San Mateo, CA")
    }

    /// The extension, MCP and add-by-URL callers never set it, so they get nil structurally rather
    /// than by remembering to pass something.
    func testAnExtensionShapedPayloadStoresNoBoardLocation() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let service = makeService(store)
        _ = try await service.ingestCapture(
            CapturePayload(
                url: "https://example.com/careers/1",
                pageTitle: "Engineer",
                visibleText: "Own monetization strategy for our platform."
            )
        )
        let captures: [Capture] = try await store.fetch(FetchDescriptor<Capture>())
        XCTAssertNil(captures.first?.boardLocation)
    }

    // MARK: - Manual override

    /// A user edit to `location` outranks both the model and the board.
    func testAManualLocationOverrideBeatsTheFilledBoardValue() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1, location: "Seattle, WA", extractionStatus: .running)
        job.manualFieldOverridesJSON = manualFieldOverrideJSON(["location"])
        try await store.insert(job)
        let request = LLMRequest(requestType: .extract, status: .running)
        request.job = job
        try await store.insert(request)

        // Exactly what the fill produces for a job whose model returned no location.
        let result = try await extract(modelLocation: "null", boardLocation: "United States, San Mateo, CA")
        XCTAssertEqual(result.location, "United States, San Mateo, CA")

        let metadata = LLMCompletionMetadata(
            requestID: request.id, jobID: job.id, attempt: 1, modelRequested: "stub-model",
            baseURL: "http://127.0.0.1:1234",
            startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2),
            durationMs: 1000
        )
        _ = try await store.commitExtractionSuccess(result, metadata: metadata)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.first?.location, "Seattle, WA")
    }
}
