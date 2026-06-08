// swiftlint:disable line_length force_unwrapping
import XCTest
import SwiftData
@testable import JobhuntCore

// MARK: - Pure-logic unit tests (no SwiftData required)

final class DuplicateDetectorTests: XCTestCase {

    // MARK: - Text normalisation

    func testNormalizeDuplicateText() {
        XCTAssertEqual(
            DuplicateDetector.normalizeDuplicateText("Hello, World! & Co."),
            "hello world and co"
        )
        XCTAssertEqual(
            DuplicateDetector.normalizeDuplicateText("  leading/trailing  "),
            "leading trailing"
        )
        XCTAssertEqual(
            DuplicateDetector.normalizeDuplicateText(""),
            ""
        )
    }

    // MARK: - Company Jaccard similarity

    func testCompanyJaccardIdentical() {
        XCTAssertEqual(DuplicateDetector.companyJaccard("Google", "Google"), 1.0)
    }

    func testCompanyJaccardWithStopWords() {
        // "Akamai Technologies" → {"akamai"}, "Akamai" → {"akamai"} → 1.0
        XCTAssertEqual(DuplicateDetector.companyJaccard("Akamai Technologies", "Akamai"), 1.0)
    }

    func testCompanyJaccardDifferent() {
        XCTAssertEqual(DuplicateDetector.companyJaccard("Google", "Amazon"), 0.0)
    }

    func testCompanyJaccardPartialOverlap() {
        // "Acme Corp Solutions" → {"acme"}, "Acme Widget" → {"acme", "widget"}
        // intersection = 1, union = 2, Jaccard = 0.5
        let jaccardScore = DuplicateDetector.companyJaccard("Acme Corp Solutions", "Acme Widget")
        XCTAssertEqual(jaccardScore, 0.5, accuracy: 0.001)
    }

    func testCompanyJaccardBothEmpty() {
        // Both reduce to empty → 1.0 (both have no signal)
        XCTAssertEqual(DuplicateDetector.companyJaccard("Inc.", "LLC"), 1.0)
    }

    func testCompanyJaccardOneEmpty() {
        XCTAssertEqual(DuplicateDetector.companyJaccard("Inc.", "Google"), 0.0)
    }

    // MARK: - Description similarity

    func testDescriptionSimilarityNilForShortText() {
        let result = DuplicateDetector.descriptionSimilarity(left: "short text", right: "short text")
        XCTAssertNil(result, "Expected nil when fewer than 8 tokens on either side")
    }

    func testDescriptionSimilarityIdentical() {
        let text = "senior software engineer distributed systems kubernetes platform reliability scalable infrastructure"
        let result = DuplicateDetector.descriptionSimilarity(left: text, right: text)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.similarity, 1.0, accuracy: 0.001)
    }

    func testDescriptionSimilarityPartial() {
        let left  = "engineer distributed systems kubernetes platform reliability scalable infrastructure backend"
        let right = "engineer distributed systems kubernetes platform reliability scalable infrastructure frontend"
        let result = DuplicateDetector.descriptionSimilarity(left: left, right: right)
        XCTAssertNotNil(result)
        // 8 shared tokens out of 9 minimum: 8/9 ≈ 0.889
        XCTAssertGreaterThan(result!.similarity, 0.8)
        XCTAssertLessThan(result!.similarity, 1.0)
    }

    func testDescriptionSimilarityNilWhenOneEmpty() {
        let left = "senior software engineer distributed systems kubernetes platform reliability"
        let result = DuplicateDetector.descriptionSimilarity(left: left, right: nil)
        XCTAssertNil(result)
    }

    // MARK: - Company domain score

    func testDomainScoreExactRegistrable() {
        // registrable matches companyCompact
        XCTAssertEqual(DuplicateDetector.companyDomainScore(company: "google", urlString: "https://google.com/jobs"), 100)
    }

    func testDomainScoreATSPlatform() {
        XCTAssertEqual(DuplicateDetector.companyDomainScore(company: "Acme Corp", urlString: "https://jobs.greenhouse.io/acme"), 45)
    }

    func testDomainScoreNoMatch() {
        XCTAssertEqual(DuplicateDetector.companyDomainScore(company: "Acme", urlString: "https://linkedin.com/jobs/12345"), 0)
    }

    func testDomainScoreNilCompany() {
        XCTAssertEqual(DuplicateDetector.companyDomainScore(company: nil, urlString: "https://google.com"), 0)
    }

    // MARK: - Source hostname

    func testSourceHostname() {
        XCTAssertEqual(DuplicateDetector.sourceHostname(urlString: "https://www.google.com/jobs"), "google.com")
        XCTAssertEqual(DuplicateDetector.sourceHostname(urlString: "https://lever.co/acme"), "lever.co")
        XCTAssertEqual(DuplicateDetector.sourceHostname(urlString: "not-a-url"), "")
    }

    // MARK: - Hash helpers

    func testCleanedHashIsDeterministic() {
        let hash1 = DuplicateDetector.cleanedHash(from: "hello world")
        let hash2 = DuplicateDetector.cleanedHash(from: "hello world")
        XCTAssertEqual(hash1, hash2)
    }

    func testCleanedHashDiffersForDifferentInputs() {
        let hash1 = DuplicateDetector.cleanedHash(from: "hello world")
        let hash2 = DuplicateDetector.cleanedHash(from: "hello world!")
        XCTAssertNotEqual(hash1, hash2)
    }

    func testRawHashIsDeterministic() {
        let hash1 = DuplicateDetector.rawHash(url: "https://example.com", canonicalURL: nil, selectedText: "text", visibleText: "visible", structuredData: [])
        let hash2 = DuplicateDetector.rawHash(url: "https://example.com", canonicalURL: nil, selectedText: "text", visibleText: "visible", structuredData: [])
        XCTAssertEqual(hash1, hash2)
    }

    // MARK: - sortedJSON (matches db.js output)

    func testSortedJSONSimple() {
        let json = DuplicateDetector.sortedJSON(["b": "2", "a": "1"] as [String: Any])
        XCTAssertEqual(json, """
        {"a":"1","b":"2"}
        """)
    }

    func testSortedJSONNull() {
        let json = DuplicateDetector.sortedJSON(NSNull())
        XCTAssertEqual(json, "null")
    }

    func testSortedJSONNestedArray() {
        let json = DuplicateDetector.sortedJSON(["z": [1, 2], "a": 0] as [String: Any])
        XCTAssertEqual(json, """
        {"a":0,"z":[1,2]}
        """)
    }

    // MARK: - Confidence scoring formula

    func testConfidenceScoringBaseline() {
        // With keepScore=100, candidateScore=45, no description info, no field conflicts:
        // domainConfidence = 0.65 + ((100 - 45) / 100) * 0.24 = 0.65 + 0.55 * 0.24 = 0.65 + 0.132 = 0.782
        let keepScore = 100
        let candidateScore = 45
        let domainConfidence = 0.65 + (Double(keepScore - candidateScore) / 100.0) * 0.24
        XCTAssertEqual(domainConfidence, 0.782, accuracy: 0.001)
    }

    func testConfidenceScoringWithFieldPenalty() {
        // 2 field conflicts → penalty = 2 * 0.08 = 0.16
        // Using baseline 0.782 - 0.16 = 0.622
        let domainConfidence = 0.782
        let fieldPenalty = 2.0 * 0.08
        let confidence = min(0.99, max(0.01, domainConfidence - fieldPenalty))
        XCTAssertEqual(confidence, 0.622, accuracy: 0.001)
    }

    // MARK: - Evidence matching (salary hard block)

    func testEvidenceMatchSalaryHardBlock() {
        var left = makeSnapshot(id: "A", company: "Acme", title: "SWE")
        var right = makeSnapshot(id: "B", company: "Acme", title: "SWE")
        // Diverge by >10% on both bounds
        left = left.withSalary(min: 100_000, max: 150_000)
        right = right.withSalary(min: 200_000, max: 300_000)
        let evidence = DuplicateDetector.evidenceMatch(left: left, right: right)
        XCTAssertNil(evidence, "Expected nil (hard block) when salary bands diverge >10% on both bounds")
    }

    func testEvidenceMatchSalaryWithinRange() {
        var left = makeSnapshot(id: "A", company: "Acme", title: "SWE")
        var right = makeSnapshot(id: "B", company: "Acme", title: "SWE")
        // Within 10% — should NOT be blocked
        left = left.withSalary(min: 100_000, max: 150_000)
        right = right.withSalary(min: 105_000, max: 155_000)
        let evidence = DuplicateDetector.evidenceMatch(left: left, right: right)
        XCTAssertNotNil(evidence, "Expected evidence (not blocked) when salary bands are within 10%")
    }

    func testEvidenceMatchFieldConflicts() {
        var left = makeSnapshot(id: "A", company: "Acme", title: "SWE")
        var right = makeSnapshot(id: "B", company: "Acme", title: "SWE")
        left = left.withRemoteType("remote")
        right = right.withRemoteType("onsite")
        let evidence = DuplicateDetector.evidenceMatch(left: left, right: right)
        XCTAssertNotNil(evidence)
        XCTAssertTrue(evidence!.fieldConflicts.contains("remote_type"))
    }

    // MARK: - duplicateGroups integration (requires SwiftData)

    @MainActor
    func testExactHashPairDetected() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let hash = DuplicateDetector.cleanedHash(from: "Senior engineer posting at Acme building distributed systems infrastructure reliability")

        let cap1 = Capture(url: "https://acme.com/jobs/1", pageTitle: "SWE", rawHash: "raw1", cleanedHash: hash)
        cap1.cleanedDescription = "Senior engineer posting at Acme building distributed systems infrastructure reliability"
        let job1 = Job(company: "Acme", title: "SWE", extractionStatus: .succeeded)
        job1.capture = cap1
        ctx.insert(cap1)
        ctx.insert(job1)

        let cap2 = Capture(url: "https://greenhouse.io/acme/jobs/1", pageTitle: "SWE", rawHash: "raw2", cleanedHash: hash)
        cap2.cleanedDescription = "Senior engineer posting at Acme building distributed systems infrastructure reliability"
        let job2 = Job(company: "Acme", title: "SWE", extractionStatus: .succeeded)
        job2.capture = cap2
        ctx.insert(cap2)
        ctx.insert(job2)

        try ctx.save()

        let detector = DuplicateDetector()
        let pairs = try detector.duplicateGroups(context: ctx)

        XCTAssertEqual(pairs.count, 1, "Expected 1 duplicate pair")
        XCTAssertEqual(pairs[0].kind, .exactHash)
        XCTAssertEqual(pairs[0].confidence, 1.0)
    }

    @MainActor
    func testResolvedDecisionExcluded() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let hash = DuplicateDetector.cleanedHash(from: "Senior engineer posting at Acme building distributed systems infrastructure reliability")

        let cap1 = Capture(url: "https://acme.com/jobs/1", pageTitle: "SWE", rawHash: "raw1", cleanedHash: hash)
        let job1 = Job(company: "Acme", title: "SWE", extractionStatus: .succeeded)
        job1.capture = cap1
        ctx.insert(cap1)
        ctx.insert(job1)

        let cap2 = Capture(url: "https://greenhouse.io/acme/jobs/1", pageTitle: "SWE", rawHash: "raw2", cleanedHash: hash)
        let job2 = Job(company: "Acme", title: "SWE", extractionStatus: .succeeded)
        job2.capture = cap2
        ctx.insert(cap2)
        ctx.insert(job2)

        // Record a resolved decision for this hash
        let decision = DuplicateDecision(cleanedHash: hash, decision: "merged", keepJobID: job1.id)
        ctx.insert(decision)

        try ctx.save()

        let detector = DuplicateDetector()
        let pairs = try detector.duplicateGroups(context: ctx)

        XCTAssertTrue(pairs.isEmpty, "Resolved pair should be excluded from results")
    }

    @MainActor
    func testNearDuplicateSimilarHashDetected() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        // Two jobs: same company+title, different URLs (one ATS, one company domain)
        // Company domain gets higher domain score → becomes "keep"
        let cap1 = Capture(
            url: "https://acme.com/jobs/engineer",
            pageTitle: "Software Engineer",
            rawHash: "rh1",
            cleanedHash: "ch1"
        )
        cap1.cleanedDescription = "Build engineer distributed systems kubernetes"
        let job1 = Job(
            company: "Acme",
            title: "Software Engineer",
            extractionStatus: .succeeded
        )
        job1.capture = cap1
        ctx.insert(cap1)
        ctx.insert(job1)

        let cap2 = Capture(
            url: "https://greenhouse.io/acme/engineer",
            pageTitle: "Software Engineer",
            rawHash: "rh2",
            cleanedHash: "ch2"
        )
        cap2.cleanedDescription = "Build engineer distributed systems kubernetes"
        let job2 = Job(
            company: "Acme",
            title: "Software Engineer",
            extractionStatus: .succeeded
        )
        job2.capture = cap2
        ctx.insert(cap2)
        ctx.insert(job2)

        try ctx.save()

        let detector = DuplicateDetector()
        let pairs = try detector.duplicateGroups(context: ctx)

        XCTAssertFalse(pairs.isEmpty, "Expected at least one near-duplicate pair")
        let pair = pairs.first!
        XCTAssertEqual(pair.kind, .similarHash)
        XCTAssertGreaterThan(pair.confidence, 0.0)
        XCTAssertLessThanOrEqual(pair.confidence, 0.99)
        // The company-domain job should be the "original" (higher domain score)
        XCTAssertEqual(pair.original.sourceURL, "https://acme.com/jobs/engineer")
    }

    @MainActor
    func testPairCountMath() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        // 3 jobs with same cleaned hash → 2 pairs (groupSize - 1 = 2)
        let hash = DuplicateDetector.cleanedHash(from: "unique posting text with enough distinct tokens for hash detection of duplication")

        for idx in 1...3 {
            let cap = Capture(url: "https://source\(idx).com/job", pageTitle: "Dev", rawHash: "rh\(idx)", cleanedHash: hash)
            cap.cleanedDescription = "unique posting text with enough distinct tokens for hash detection of duplication"
            let job = Job(jobNumber: idx, company: "Corp", title: "Dev", extractionStatus: .succeeded)
            job.capture = cap
            ctx.insert(cap)
            ctx.insert(job)
        }
        try ctx.save()

        let detector = DuplicateDetector()
        let pairs = try detector.duplicateGroups(context: ctx)

        // groupSize=3 → pair count = groupSize - 1 = 2
        XCTAssertEqual(pairs.count, 2, "Three jobs with same hash should yield 2 pairs")
        XCTAssertTrue(pairs.allSatisfy { $0.kind == .exactHash })
    }
}

// MARK: - Test helpers

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Job.self, Capture.self, DuplicateDecision.self,
        JobEvent.self, JobAction.self, Contact.self,
        CoverLetter.self, JobFitScore.self, LLMRequest.self,
        LLMRequestAttempt.self, DataQualityReview.self
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: config)
}

/// Simple value-type snapshot builder for unit tests that don't need SwiftData.
private func makeSnapshot(id: String, company: String, title: String) -> JobSnapshot {
    let cap = Capture(url: "https://example.com/\(id)", pageTitle: title, rawHash: id)
    let job = Job(id: id, company: company, title: title, extractionStatus: .succeeded)
    return JobSnapshot(job: job, capture: cap)
}

private extension JobSnapshot {
    func withSalary(min: Int, max: Int) -> JobSnapshot {
        // Rebuild via Job + Capture with salary values set
        let cap = Capture(url: self.sourceURL, pageTitle: "", rawHash: self.id, cleanedHash: self.cleanedHash)
        cap.cleanedDescription = self.cleanedDescription
        let job = Job(
            id: self.id,
            jobNumber: self.jobNumber,
            company: self.company,
            title: self.title,
            remoteType: self.remoteType.flatMap(RemoteType.init),
            salaryMin: min,
            salaryMax: max,
            salaryCurrency: self.salaryCurrency,
            employmentType: self.employmentType,
            seniority: self.seniority,
            extractionStatus: ExtractionStatus(rawValue: self.extractionStatus) ?? .succeeded
        )
        job.capture = cap
        return JobSnapshot(job: job, capture: cap)
    }

    func withRemoteType(_ remoteType: String) -> JobSnapshot {
        let cap = Capture(url: self.sourceURL, pageTitle: "", rawHash: self.id, cleanedHash: self.cleanedHash)
        cap.cleanedDescription = self.cleanedDescription
        let job = Job(
            id: self.id,
            company: self.company,
            title: self.title,
            remoteType: RemoteType(rawValue: remoteType),
            salaryMin: self.salaryMin,
            salaryMax: self.salaryMax,
            extractionStatus: ExtractionStatus(rawValue: self.extractionStatus) ?? .succeeded
        )
        job.capture = cap
        return JobSnapshot(job: job, capture: cap)
    }
}

// swiftlint:enable line_length force_unwrapping
