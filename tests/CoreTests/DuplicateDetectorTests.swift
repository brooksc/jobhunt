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

    // TASK-581: the shared count helper used by dashboard, sidebar, and Duplicates screen.
    @MainActor
    func testUnresolvedPairCountSharedHelper() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let desc = "Senior engineer posting at Acme building distributed systems infrastructure reliability"
        let hash = DuplicateDetector.cleanedHash(from: desc)

        let cap1 = Capture(url: "https://acme.com/jobs/1", pageTitle: "SWE", rawHash: "raw1", cleanedHash: hash)
        cap1.cleanedDescription = desc
        let job1 = Job(company: "Acme", title: "SWE", extractionStatus: .succeeded)
        job1.capture = cap1
        let cap2 = Capture(
            url: "https://greenhouse.io/acme/jobs/1",
            pageTitle: "SWE",
            rawHash: "raw2",
            cleanedHash: hash
        )
        cap2.cleanedDescription = desc
        let job2 = Job(company: "Acme", title: "SWE", extractionStatus: .succeeded)
        job2.capture = cap2
        ctx.insert(cap1)
        ctx.insert(cap2)
        ctx.insert(job1)
        ctx.insert(job2)
        try ctx.save()

        // Two un-marked jobs sharing a cleaned hash → one unresolved review pair.
        XCTAssertEqual(DuplicateDetector.unresolvedPairCount(jobs: [job1, job2], decisions: []), 1)

        // A job already marked `.duplicate` is resolved → excluded by reviewSnapshots.
        job2.status = .duplicate
        XCTAssertEqual(DuplicateDetector.unresolvedPairCount(jobs: [job1, job2], decisions: []), 0)
        job2.status = .new

        // A resolved decision for the hash suppresses the pair.
        let decision = DuplicateDecision(cleanedHash: hash, decision: "merged", keepJobID: job1.id)
        XCTAssertEqual(DuplicateDetector.unresolvedPairCount(jobs: [job1, job2], decisions: [decision]), 0)
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

    /// TASK-605: the same posting captured from an aggregator and the company's ATS, whose titles
    /// differ only by a "(Remote)" qualifier, must still be surfaced as a duplicate pair. Before the
    /// fix the "(Remote)" token split them into different title groups so they were never compared.
    func testDetectDomainDuplicates_titleDiffersOnlyByRemoteQualifier_isPaired() {
        let detector = DuplicateDetector()
        let sharedDesc = "lead cross functional program roadmap delivery stakeholders curriculum assessment "
            + "childhood education platform milestones dependencies launch"

        // #163 — aggregator source, bare title, location "Texas".
        let aggCap = Capture(
            url: "https://www.remoterocketship.com/us/publicjobs/company/teaching-strategies-llc/jobs/principal-tpm",
            pageTitle: "Principal Technical Program Manager", rawHash: "rh-163", cleanedHash: "ch-163"
        )
        aggCap.cleanedDescription = sharedDesc
        let aggJob = Job(
            company: "Teaching Strategies, LLC",
            title: "Principal Technical Program Manager",
            extractionStatus: .succeeded
        )
        aggJob.location = "Texas"
        aggJob.capture = aggCap

        // #193 — the company ATS (pinpointhq), title has "(Remote)", location "Denton, Texas".
        let atsCap = Capture(
            url: "https://teaching-strategies.pinpointhq.com/en/postings/abc",
            pageTitle: "Principal Technical Program Manager (Remote)", rawHash: "rh-193", cleanedHash: "ch-193"
        )
        atsCap.cleanedDescription = sharedDesc
        let atsJob = Job(
            company: "Teaching Strategies, LLC",
            title: "Principal Technical Program Manager (Remote)",
            extractionStatus: .succeeded
        )
        atsJob.location = "Denton, Texas"
        atsJob.capture = atsCap

        let snapshots = [JobSnapshot(job: aggJob, capture: aggCap), JobSnapshot(job: atsJob, capture: atsCap)]
        let pairs = detector.duplicateGroups(snapshots: snapshots, resolvedHashes: [])
        XCTAssertEqual(pairs.count, 1, "cross-source pair differing only by a (Remote) title qualifier must be found")
        // The ATS (pinpointhq) is the higher-authority source, so it's the preferred original.
        XCTAssertEqual(pairs.first?.original.id, atsJob.id)
        XCTAssertEqual(pairs.first?.candidate.id, aggJob.id)
    }

    // MARK: - TASK-620: aggressive recall (ATS id, same-host, fuzzy title)

    private func snap(
        _ number: Int, company: String, title: String, url: String,
        status: JobStatus = .pursuing,
        desc: String = "shared job posting description with enough meaningful distinct tokens for evidence here today"
    ) -> JobSnapshot {
        let cap = Capture(url: url, pageTitle: title, rawHash: "rh\(number)", cleanedHash: "ch\(number)")
        cap.cleanedDescription = desc
        let job = Job(jobNumber: number, company: company, title: title, status: status, extractionStatus: .succeeded)
        job.capture = cap
        return JobSnapshot(job: job, capture: cap)
    }

    // MARK: - TASK-629: same full URL (query included) is a definitive duplicate

    /// The real Reddit #15/#16 case: byte-identical levels.fyi URL (incl. jobId), captured seconds apart,
    /// whose SPA DOM differed enough to give distinct cleaned hashes. The same-URL path makes it a
    /// definitive duplicate (1.0), outranking the fuzzy heuristic that previously surfaced it at ~80%.
    func testSameFullURL_pairsAsDefinitiveDuplicate() {
        let url = "https://www.levels.fyi/jobs/title/technical-program-manager"
            + "?locationSlug=united-states&offset=5&perkIds=58&jobId=119440407640580806"
        let a = snap(
            15,
            company: "Reddit",
            title: "Principal Technical Program Manager, Developer Productivity",
            url: url
        )
        let b = snap(
            16,
            company: "Reddit",
            title: "Principal Technical Program Manager, Developer Productivity",
            url: url
        )
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [a, b], resolvedHashes: [])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.kind, .sameURL, "identical full URL should win over the fuzzy path")
        XCTAssertEqual(pairs.first?.confidence, 1.0)
        XCTAssertEqual(pairs.first?.original.jobNumber, 15, "earlier capture is canonical")
    }

    /// Query-order / trailing-slash differences on the same posting still match (normalized key).
    func testSameFullURL_matchesDespiteQueryOrderAndTrailingSlash() {
        let a = snap(1, company: "Reddit", title: "Staff TPM", url: "https://x.com/jobs/?b=2&a=1&jobId=99")
        let b = snap(2, company: "Reddit", title: "Staff TPM", url: "https://x.com/jobs?a=1&jobId=99&b=2")
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [a, b], resolvedHashes: [])
        XCTAssertEqual(pairs.first?.kind, .sameURL)
    }

    /// Query-less generic/SPA URLs must NOT collapse unrelated jobs — the same-URL path requires a query.
    func testQuerylessSameURL_doesNotTriggerSameURLPath() {
        let a = snap(1, company: "Foo", title: "Staff Engineer", url: "https://careers.foo.com/openings")
        let b = snap(2, company: "Bar", title: "Marketing Lead", url: "https://careers.foo.com/openings")
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [a, b], resolvedHashes: [])
        XCTAssertTrue(pairs.allSatisfy { $0.kind != .sameURL }, "query-less URL must not form a same-URL pair")
    }

    /// Different jobId in the query → different keys → no same-URL pair (distinct postings on one page).
    func testDifferentQueryID_noSameURLPair() {
        let a = snap(1, company: "Reddit", title: "Alpha Role", url: "https://x.com/jobs?jobId=111")
        let b = snap(2, company: "Reddit", title: "Beta Role", url: "https://x.com/jobs?jobId=222")
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [a, b], resolvedHashes: [])
        XCTAssertTrue(pairs.allSatisfy { $0.kind != .sameURL }, "different jobId must not pair via same-URL")
    }

    func testSpecificFullURLKey_requiresQueryAndNormalizes() {
        XCTAssertNil(DuplicateDetector.specificFullURLKey("https://x.com/jobs"), "no query → nil")
        XCTAssertNil(DuplicateDetector.specificFullURLKey("https://x.com/jobs/"), "no query → nil")
        let k1 = DuplicateDetector.specificFullURLKey("https://X.com/jobs/?b=2&a=1")
        let k2 = DuplicateDetector.specificFullURLKey("https://x.com/jobs?a=1&b=2")
        XCTAssertNotNil(k1)
        XCTAssertEqual(k1, k2, "host case, query order, and trailing slash are normalized")
    }

    /// A: the ATS posting id is extracted across the providers seen in the real data.
    func testATSPostingID_extractsAcrossProviders() {
        let cases: [(String, String?)] = [
            ("https://www.pinterestcareers.com/jobs/?gh_jid=7957799", "gh:7957799"),
            ("https://www.pinterestcareers.com/jobs/7957799/staff-tpm/?gh_jid=7957799", "gh:7957799"),
            ("https://job-boards.greenhouse.io/securityscorecard/jobs/7974857", "gh:7974857"),
            ("https://www.linkedin.com/jobs/view/4424422798/?trackingId=x", "li:4424422798"),
            ("https://www.linkedin.com/jobs/search/?currentJobId=4442611206&start=25", "li:4442611206"),
            (
                "https://zillow.wd5.myworkdayjobs.com/en-US/Zillow_Group_External/details/Role_P750335-1?x=1",
                "wd:zillow:P750335"
            ),
            (
                "https://zillow.wd5.myworkdayjobs.com/zillow_group_external/job/Remote-USA/Role_P750335-1",
                "wd:zillow:P750335"
            ),
            ("https://jobs.ashbyhq.com/far.ai/00763d58-c6ae-4334-a5", "ashby:far.ai:00763d58-c6ae-4334-a5"),
            ("https://example.com/careers/some-role", nil)
        ]
        for (url, expected) in cases {
            XCTAssertEqual(DuplicateDetector.atsPostingID(urlString: url), expected, "url: \(url)")
        }
    }

    /// A: same gh_jid captured from two URL forms is a duplicate — even when the titles differ (the
    /// `?gh_jid=` landing page mis-captured a title). Real jobs #122/#329.
    func testSameATSPostingID_pairsEvenWhenTitlesDiffer() {
        let a = snap(
            122,
            company: "Pinterest",
            title: "Staff Technical Program Manager ML/AI Platform",
            url: "https://www.pinterestcareers.com/jobs/7494634/staff-tpm/?gh_jid=7494634"
        )
        let b = snap(
            329,
            company: "Pinterest",
            title: "Staff Technical Program Manager, Compute Infrastructure",
            url: "https://www.pinterestcareers.com/jobs/?gh_jid=7494634"
        )
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [a, b], resolvedHashes: [])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.kind, .atsPostingID)
        XCTAssertEqual(pairs.first?.original.id, a.id, "earlier job number is the canonical")
    }

    /// B: same company + same title on the SAME host (different req ids) — a repost — is now surfaced
    /// (previously the two-distinct-hostname requirement skipped it). Real jobs #148/#361.
    func testSameHostSameTitle_isPaired() {
        let a = snap(
            148,
            company: "SecurityScorecard",
            title: "Senior/Principal Product Manager, AI",
            url: "https://job-boards.greenhouse.io/securityscorecard/jobs/7974857"
        )
        let b = snap(
            361,
            company: "SecurityScorecard",
            title: "Senior/Principal Product Manager, AI",
            url: "https://job-boards.greenhouse.io/securityscorecard/jobs/7961068"
        )
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [a, b], resolvedHashes: [])
        XCTAssertEqual(pairs.count, 1, "same-host same-title repost should be surfaced")
    }

    /// TASK-626 (the Guild case): a live candidate must NOT pair against an EXPIRED original — that would
    /// push the user to mark the job they're pursuing as a duplicate of a dead posting. Expired/rejected
    /// jobs are excluded from dedup candidates.
    func testExpiredOriginal_doesNotPairWithLiveCandidate() {
        let expired = snap(
            10,
            company: "Guild",
            title: "Staff Technical Program Manager",
            url: "https://guild.com/careers/staff-tpm",
            status: .expired
        )
        let live = snap(
            20,
            company: "Guild",
            title: "Staff Technical Program Manager",
            url: "https://www.linkedin.com/jobs/view/4442490941",
            status: .pursuing
        )
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [expired, live], resolvedHashes: [])
        XCTAssertTrue(pairs.isEmpty, "expired original must not form a review pair with a live candidate")
    }

    /// C: aggregator vs company site whose title differs only by a suffix ("…, Toast IQ"). Real
    /// jobs #165/#304.
    func testFuzzyTitleSuffix_isPaired() {
        let agg = snap(
            165,
            company: "Toast",
            title: "Principal Technical Program Manager",
            url: "https://www.remoterocketship.com/us/publicjobs/company/toasttab/jobs/principal-tpm/"
        )
        let site = snap(
            304,
            company: "Toast",
            title: "Principal Technical Program Manager, Toast IQ",
            url: "https://careers.toasttab.com/jobs?gh_jid=8054004"
        )
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [agg, site], resolvedHashes: [])
        XCTAssertEqual(pairs.count, 1, "title-suffix variant across sources should be surfaced")
    }

    /// Guard: different LEVELS of the same role at one company must NOT merge (Senior vs Staff). Real
    /// ClickUp jobs #255/#208.
    func testDifferentLevelsSameCompany_notPaired() {
        let senior = snap(
            255,
            company: "ClickUp",
            title: "Senior Product Manager",
            url: "https://www.linkedin.com/jobs/search/?currentJobId=1"
        )
        let staff = snap(
            208,
            company: "ClickUp",
            title: "Staff Product Manager",
            url: "https://www.linkedin.com/jobs/search/?currentJobId=2"
        )
        let pairs = DuplicateDetector().duplicateGroups(snapshots: [senior, staff], resolvedHashes: [])
        XCTAssertTrue(pairs.isEmpty, "different seniority levels of the same role must not be flagged")
    }

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

    // MARK: - duplicatePairForCandidate (incremental per-job check, TASK-611)

    private func hashSnapshot(id: String, jobNumber: Int, url: String, hash: String) -> JobSnapshot {
        let cap = Capture(url: url, pageTitle: "Software Engineer", rawHash: "rh_\(id)", cleanedHash: hash)
        cap.cleanedDescription =
            "Shared boilerplate duplicate listing carrying sufficient distinct meaningful unique tokens here"
        let job = Job(id: id, company: "AcmeCorp", title: "Software Engineer", extractionStatus: .succeeded)
        job.jobNumber = jobNumber
        job.capture = cap
        return JobSnapshot(job: job, capture: cap)
    }

    func testDuplicatePairForCandidate_flagsExactHashDuplicate() {
        let hash = "shared_ch"
        let original = hashSnapshot(id: "orig", jobNumber: 1, url: "https://acme.com/job", hash: hash)
        let candidate = hashSnapshot(id: "cand", jobNumber: 2, url: "https://greenhouse.io/acme/job", hash: hash)
        let pair = DuplicateDetector().duplicatePairForCandidate(candidate, among: [original], resolvedHashes: [])
        XCTAssertEqual(pair?.candidate.id, "cand")
        XCTAssertEqual(pair?.original.id, "orig", "the earlier job is the canonical original")
    }

    func testDuplicatePairForCandidate_returnsNilForUniqueJob() {
        let candidate = hashSnapshot(id: "a", jobNumber: 1, url: "https://a.com/job", hash: "hash_a")
        let unrelated = hashSnapshot(id: "b", jobNumber: 2, url: "https://b.com/job", hash: "hash_b")
        // Different titles would normally differ too, but even with the same title a different hash and
        // single hostname yields no pair — nothing for the candidate to duplicate.
        XCTAssertNil(DuplicateDetector().duplicatePairForCandidate(candidate, among: [unrelated], resolvedHashes: []))
    }

    func testDuplicatePairForCandidate_respectsResolvedHashes() {
        let hash = "shared_ch"
        let original = hashSnapshot(id: "orig", jobNumber: 1, url: "https://acme.com/job", hash: hash)
        let candidate = hashSnapshot(id: "cand", jobNumber: 2, url: "https://greenhouse.io/acme/job", hash: hash)
        let pair = DuplicateDetector().duplicatePairForCandidate(
            candidate, among: [original], resolvedHashes: [hash]
        )
        XCTAssertNil(pair, "a resolved hash must not re-flag the candidate")
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
