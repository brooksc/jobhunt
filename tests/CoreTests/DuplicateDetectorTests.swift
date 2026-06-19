import SwiftData

// swiftlint:disable line_length
import XCTest
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

    func testDescriptionSimilarityIdentical() throws {
        let text = "senior software engineer distributed systems kubernetes platform reliability scalable infrastructure"
        let result = DuplicateDetector.descriptionSimilarity(left: text, right: text)
        XCTAssertNotNil(result)
        XCTAssertEqual(try XCTUnwrap(result?.similarity), 1.0, accuracy: 0.001)
    }

    func testDescriptionSimilarityPartial() throws {
        let left = "engineer distributed systems kubernetes platform reliability scalable infrastructure backend"
        let right = "engineer distributed systems kubernetes platform reliability scalable infrastructure frontend"
        let result = DuplicateDetector.descriptionSimilarity(left: left, right: right)
        XCTAssertNotNil(result)
        // 8 shared tokens out of 9 minimum: 8/9 ≈ 0.889
        XCTAssertGreaterThan(try XCTUnwrap(result?.similarity), 0.8)
        XCTAssertLessThan(try XCTUnwrap(result?.similarity), 1.0)
    }

    func testDescriptionSimilarityNilWhenOneEmpty() {
        let left = "senior software engineer distributed systems kubernetes platform reliability"
        let result = DuplicateDetector.descriptionSimilarity(left: left, right: nil)
        XCTAssertNil(result)
    }

    // MARK: - Company domain score

    func testDomainScoreExactRegistrable() {
        // registrable matches companyCompact
        XCTAssertEqual(
            DuplicateDetector.companyDomainScore(company: "google", urlString: "https://google.com/jobs"),
            100
        )
    }

    func testDomainScoreATSPlatform() {
        XCTAssertEqual(
            DuplicateDetector.companyDomainScore(company: "Acme Corp", urlString: "https://jobs.greenhouse.io/acme"),
            45
        )
    }

    func testDomainScoreNoMatch() {
        XCTAssertEqual(
            DuplicateDetector.companyDomainScore(company: "Acme", urlString: "https://linkedin.com/jobs/12345"),
            0
        )
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
        let hash1 = DuplicateDetector.rawHash(
            url: "https://example.com",
            canonicalURL: nil,
            selectedText: "text",
            visibleText: "visible",
            structuredData: []
        )
        let hash2 = DuplicateDetector.rawHash(
            url: "https://example.com",
            canonicalURL: nil,
            selectedText: "text",
            visibleText: "visible",
            structuredData: []
        )
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

    func testEvidenceMatchFieldConflicts() throws {
        var left = makeSnapshot(id: "A", company: "Acme", title: "SWE")
        var right = makeSnapshot(id: "B", company: "Acme", title: "SWE")
        left = left.withRemoteType("remote")
        right = right.withRemoteType("onsite")
        let evidence = DuplicateDetector.evidenceMatch(left: left, right: right)
        XCTAssertNotNil(evidence)
        XCTAssertTrue(try XCTUnwrap(evidence?.fieldConflicts.contains("remote_type")))
    }

    // MARK: - duplicateGroups integration (requires SwiftData)

    @MainActor
    func testExactHashPairDetected() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let hash = DuplicateDetector
            .cleanedHash(
                from: "Senior engineer posting at Acme building distributed systems infrastructure reliability"
            )

        let cap1 = Capture(url: "https://acme.com/jobs/1", pageTitle: "SWE", rawHash: "raw1", cleanedHash: hash)
        cap1.cleanedDescription = "Senior engineer posting at Acme building distributed systems infrastructure reliability"
        let job1 = Job(company: "Acme", title: "SWE", extractionStatus: .succeeded)
        job1.capture = cap1
        ctx.insert(cap1)
        ctx.insert(job1)

        let cap2 = Capture(
            url: "https://greenhouse.io/acme/jobs/1",
            pageTitle: "SWE",
            rawHash: "raw2",
            cleanedHash: hash
        )
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

        let hash = DuplicateDetector
            .cleanedHash(
                from: "Senior engineer posting at Acme building distributed systems infrastructure reliability"
            )

        let sharedDesc = "Senior engineer posting at Acme building distributed systems infrastructure reliability"
        let cap1 = Capture(url: "https://acme.com/jobs/1", pageTitle: "SWE", rawHash: "raw1", cleanedHash: hash)
        cap1.cleanedDescription = sharedDesc
        let job1 = Job(company: "Acme", title: "SWE", extractionStatus: .succeeded)
        job1.capture = cap1
        ctx.insert(cap1)
        ctx.insert(job1)

        let cap2 = Capture(
            url: "https://greenhouse.io/acme/jobs/1",
            pageTitle: "SWE",
            rawHash: "raw2",
            cleanedHash: hash
        )
        cap2.cleanedDescription = sharedDesc
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
        let pair = try XCTUnwrap(pairs.first)
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
        let hash = DuplicateDetector
            .cleanedHash(from: "unique posting text with enough distinct tokens for hash detection of duplication")

        for idx in 1 ... 3 {
            let cap = Capture(
                url: "https://source\(idx).com/job",
                pageTitle: "Dev",
                rawHash: "rh\(idx)",
                cleanedHash: hash
            )
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

    /// TASK-143 regression: snapshot-based overload matches context-based result.
    /// Verifies that duplicateGroups(snapshots:resolvedHashes:) produces the same pairs
    /// as the context-based overload, enabling off-main-actor computation.
    @MainActor
    func testSnapshotOverloadMatchesContextOverload() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let snapDesc = "snapshot overload regression posting with sufficient distinct meaningful tokens here today"
        let hash = DuplicateDetector.cleanedHash(from: snapDesc)
        for idx in 1 ... 2 {
            let cap = Capture(
                url: "https://site\(idx).com/job",
                pageTitle: "Eng",
                rawHash: "rh_snap\(idx)",
                cleanedHash: hash
            )
            cap.cleanedDescription = snapDesc
            let job = Job(jobNumber: idx, company: "SnapCo", title: "Eng", extractionStatus: .succeeded)
            job.capture = cap
            ctx.insert(cap)
            ctx.insert(job)
        }
        try ctx.save()

        let contextPairs = try DuplicateDetector().duplicateGroups(context: ctx)

        let allJobs = try ctx.fetch(FetchDescriptor<Job>())
        let snapshots = allJobs.compactMap { job -> JobSnapshot? in
            guard let cap = job.capture else { return nil }
            return JobSnapshot(job: job, capture: cap)
        }
        let snapshotPairs = DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: [])

        XCTAssertEqual(contextPairs.count, snapshotPairs.count)
        let contextKeys = Set(contextPairs.map { "\($0.original.id)||\($0.candidate.id)" })
        let snapshotKeys = Set(snapshotPairs.map { "\($0.original.id)||\($0.candidate.id)" })
        XCTAssertEqual(contextKeys, snapshotKeys, "Snapshot overload must produce same pairs as context overload")
    }

    // MARK: - Performance benchmark (TASK-212)

    /// Verifies that duplicate detection over 500+ synthetic jobs completes within a
    /// reasonable wall-clock budget. The synthetic set contains:
    ///   - 200 unique jobs (no duplicates expected)
    ///   - 150 exact-hash duplicate pairs (300 jobs)
    ///   - 50 near-duplicate clusters of 2 (100 jobs, different URLs)
    /// Total: 600 snapshots, covering the O(N²) worst-case paths.
    func testDuplicateDetectionPerformanceLargeDataset() {
        let detector = DuplicateDetector()

        // Build 600 synthetic snapshots
        var snapshots: [JobSnapshot] = []

        // 200 unique jobs — no matches
        for i in 0 ..< 200 {
            let cap = Capture(
                url: "https://unique-site\(i).example.com/job",
                pageTitle: "Unique Role \(i)",
                rawHash: "unique_rh_\(i)",
                cleanedHash: "unique_ch_\(i)"
            )
            cap.cleanedDescription = "Unique description number \(i) with enough tokens for signal detection purposes here"
            let job = Job(
                jobNumber: i,
                company: "UniqueCompany\(i)",
                title: "Unique Engineer \(i)",
                extractionStatus: .succeeded
            )
            job.capture = cap
            snapshots.append(JobSnapshot(job: job, capture: cap))
        }

        // 150 exact-hash pairs (300 jobs) — same cleanedHash, different URLs
        for i in 0 ..< 150 {
            let sharedHash = "shared_hash_\(i)"
            let sharedDesc = "Shared boilerplate duplicate listing pair \(i) carrying sufficient distinct meaningful unique tokens"
            for urlIdx in 0 ..< 2 {
                let url = urlIdx == 0
                    ? "https://acme\(i).com/job"
                    : "https://greenhouse.io/acme\(i)/job"
                let cap = Capture(
                    url: url,
                    pageTitle: "Shared Role \(i)",
                    rawHash: "shared_rh_\(i)_\(urlIdx)",
                    cleanedHash: sharedHash
                )
                cap.cleanedDescription = sharedDesc
                let job = Job(
                    jobNumber: 200 + i * 2 + urlIdx,
                    company: "AcmeCorp\(i)",
                    title: "Software Engineer",
                    extractionStatus: .succeeded
                )
                job.capture = cap
                snapshots.append(JobSnapshot(job: job, capture: cap))
            }
        }

        // 50 near-duplicate clusters (100 jobs): same title+company, different hostnames
        for i in 0 ..< 50 {
            let desc = "Platform engineer kubernetes distributed systems reliability infrastructure cloud scale \(i)"
            for urlIdx in 0 ..< 2 {
                let url = urlIdx == 0
                    ? "https://nearco\(i).com/platform-eng"
                    : "https://jobs.greenhouse.io/nearco\(i)"
                let cap = Capture(
                    url: url,
                    pageTitle: "Platform Engineer",
                    rawHash: "near_rh_\(i)_\(urlIdx)",
                    cleanedHash: "near_ch_\(i)_\(urlIdx)"
                )
                cap.cleanedDescription = desc
                let job = Job(
                    jobNumber: 500 + i * 2 + urlIdx,
                    company: "NearCo\(i)",
                    title: "Platform Engineer",
                    extractionStatus: .succeeded
                )
                job.capture = cap
                snapshots.append(JobSnapshot(job: job, capture: cap))
            }
        }

        XCTAssertEqual(snapshots.count, 600, "Expected 600 synthetic snapshots")

        // CPU time (not wall-clock) is unaffected by OS scheduling and process suspension,
        // so this measurement stays reliable even when the machine is under heavy load.
        var pairs: [DuplicatePair] = []
        measure(metrics: [XCTCPUMetric()]) {
            pairs = detector.duplicateGroups(snapshots: snapshots, resolvedHashes: [])
        }

        // Sanity-check: exact-hash pairs should be found
        let exactPairs = pairs.filter { $0.kind == .exactHash }
        XCTAssertEqual(exactPairs.count, 150, "Expected 150 exact-hash pairs")
    }

    // MARK: - Exact-hash collisions across unrelated companies must NOT be flagged

    /// Regression: a generic/boilerplate description that hash-collides across different
    /// employers (e.g. Elastic vs Stripe) must not be reported as a duplicate.
    func testExactHashAcrossDifferentCompaniesNotFlagged() {
        let sharedDesc = "Generic boilerplate posting text shared across unrelated companies with enough tokens"
        let hash = DuplicateDetector.cleanedHash(from: sharedDesc)

        var snapshots: [JobSnapshot] = []
        for (idx, company) in ["Elastic", "Stripe", "Cayuse LLC", "Luma AI"].enumerated() {
            let cap = Capture(
                url: "https://site\(idx).com/job",
                pageTitle: "PM",
                rawHash: "rh\(idx)",
                cleanedHash: hash
            )
            cap.cleanedDescription = sharedDesc
            let job = Job(jobNumber: idx, company: company, title: "Program Manager", extractionStatus: .succeeded)
            job.capture = cap
            snapshots.append(JobSnapshot(job: job, capture: cap))
        }

        let pairs = DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: [])
        XCTAssertTrue(
            pairs.isEmpty,
            "Different companies sharing a cleaned-description hash must not be flagged as duplicates"
        )
    }

    /// A hash group with two same-company jobs and one different-company job yields exactly
    /// one pair (the same-company captures); the unrelated company is left out.
    func testExactHashMixedCompaniesPairsOnlySameCompany() {
        let sharedDesc = "Shared posting text that collides on hash across multiple captures with enough tokens here"
        let hash = DuplicateDetector.cleanedHash(from: sharedDesc)

        var snapshots: [JobSnapshot] = []
        for (idx, company) in ["Acme", "Acme", "Globex"].enumerated() {
            let cap = Capture(
                url: "https://site\(idx).com/job",
                pageTitle: "Eng",
                rawHash: "rh\(idx)",
                cleanedHash: hash
            )
            cap.cleanedDescription = sharedDesc
            let job = Job(jobNumber: idx, company: company, title: "Engineer", extractionStatus: .succeeded)
            job.capture = cap
            snapshots.append(JobSnapshot(job: job, capture: cap))
        }

        let pairs = DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: [])
        let exactPairs = pairs.filter { $0.kind == .exactHash }
        XCTAssertEqual(exactPairs.count, 1, "Only the two same-company captures should pair")
        XCTAssertEqual(exactPairs.first?.original.company, "Acme")
        XCTAssertEqual(exactPairs.first?.candidate.company, "Acme")
    }

    /// Regression: two same-company jobs whose cleaned description is trivial boilerplate
    /// (e.g. a lone "$" — the real-world capture-failure case) must not pair on exact hash.
    /// The company guard alone would let these through; the min-content guard blocks them.
    func testExactHashShortDescriptionSameCompanyNotFlagged() {
        let sharedDesc = "$"
        let hash = DuplicateDetector.cleanedHash(from: sharedDesc)

        var snapshots: [JobSnapshot] = []
        for idx in 0 ..< 2 {
            let cap = Capture(
                url: "https://acme.com/job\(idx)",
                pageTitle: "Eng",
                rawHash: "rh\(idx)",
                cleanedHash: hash
            )
            cap.cleanedDescription = sharedDesc
            let job = Job(jobNumber: idx, company: "Acme", title: "Engineer \(idx)", extractionStatus: .succeeded)
            job.capture = cap
            snapshots.append(JobSnapshot(job: job, capture: cap))
        }

        let pairs = DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: [])
        XCTAssertTrue(
            pairs.isEmpty,
            "Trivial boilerplate descriptions must not anchor an exact-hash duplicate, even within one company"
        )
    }

    // MARK: - TASK-252: already-resolved duplicates excluded from detection candidates

    func testDetectDomainDuplicates_alreadyMarkedDuplicate_notSurfacedAsCandidate() {
        let detector = DuplicateDetector()

        // "keep" job: company domain, high score
        let keepCap = Capture(
            url: "https://acme.com/jobs/engineer",
            pageTitle: "Software Engineer",
            rawHash: "rh-keep",
            cleanedHash: "ch-keep"
        )
        keepCap.cleanedDescription = "Build distributed systems kubernetes infrastructure reliability platform scale"
        let keepJob = Job(company: "Acme", title: "Software Engineer", extractionStatus: .succeeded)
        keepJob.capture = keepCap

        // Candidate job that was ALREADY marked as a duplicate — must be excluded
        let dupCap = Capture(
            url: "https://greenhouse.io/acme/engineer",
            pageTitle: "Software Engineer",
            rawHash: "rh-dup",
            cleanedHash: "ch-dup"
        )
        dupCap.cleanedDescription = "Build distributed systems kubernetes infrastructure reliability platform scale"
        let dupJob = Job(company: "Acme", title: "Software Engineer", status: .duplicate, extractionStatus: .succeeded)
        dupJob.duplicateOfJobID = keepJob.id
        dupJob.capture = dupCap

        let snapshots = [
            JobSnapshot(job: keepJob, capture: keepCap),
            JobSnapshot(job: dupJob, capture: dupCap)
        ]

        let pairs = detector.duplicateGroups(snapshots: snapshots, resolvedHashes: [])
        XCTAssertTrue(pairs.isEmpty, "A job already marked as duplicate must not surface as a detection candidate")
    }

    /// TASK-143 regression: resolved hashes passed via Set must suppress matching pairs.
    func testSnapshotOverloadRespectsResolvedHashes() {
        let resolvedDesc = "already resolved unique hash text with enough meaningful tokens here detection"
        let hash = DuplicateDetector.cleanedHash(from: resolvedDesc)
        var snapshots: [JobSnapshot] = []
        for idx in 1 ... 2 {
            let cap = Capture(url: "https://s\(idx).com/j", pageTitle: "Job", rawHash: "rh\(idx)", cleanedHash: hash)
            cap.cleanedDescription = resolvedDesc
            let job = Job(jobNumber: idx, company: "Co", title: "Job", extractionStatus: .succeeded)
            job.capture = cap
            snapshots.append(JobSnapshot(job: job, capture: cap))
        }

        let unresolved = DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: [])
        XCTAssertEqual(unresolved.count, 1, "One pair expected before resolution")

        let resolved = DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: [hash])
        XCTAssertEqual(resolved.count, 0, "Pair must be suppressed when hash is in resolvedHashes")
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
        let cap = Capture(url: sourceURL, pageTitle: "", rawHash: id, cleanedHash: cleanedHash)
        cap.cleanedDescription = cleanedDescription
        let job = Job(
            id: id,
            jobNumber: jobNumber,
            company: company,
            title: title,
            remoteType: remoteType.flatMap(RemoteType.init),
            salaryMin: min,
            salaryMax: max,
            salaryCurrency: salaryCurrency,
            employmentType: employmentType,
            seniority: seniority,
            extractionStatus: ExtractionStatus(rawValue: extractionStatus) ?? .succeeded
        )
        job.capture = cap
        return JobSnapshot(job: job, capture: cap)
    }

    func withRemoteType(_ remoteType: String) -> JobSnapshot {
        let cap = Capture(url: sourceURL, pageTitle: "", rawHash: id, cleanedHash: cleanedHash)
        cap.cleanedDescription = cleanedDescription
        let job = Job(
            id: id,
            company: company,
            title: title,
            remoteType: RemoteType(rawValue: remoteType),
            salaryMin: salaryMin,
            salaryMax: salaryMax,
            extractionStatus: ExtractionStatus(rawValue: extractionStatus) ?? .succeeded
        )
        job.capture = cap
        return JobSnapshot(job: job, capture: cap)
    }
}

// swiftlint:enable line_length
