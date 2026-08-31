import CryptoKit

// swiftlint:disable file_length type_body_length large_tuple
import Foundation
import SwiftData

// MARK: - Public types

/// A candidate duplicate pair produced by DuplicateDetector.
public struct DuplicatePair: Sendable {
    /// The preferred / canonical job (higher domain-authority source).
    public let original: JobSnapshot
    /// The suspected duplicate job.
    public let candidate: JobSnapshot
    /// Confidence that `candidate` duplicates `original` (0–1).
    public let confidence: Double
    /// Human-readable reason string (matches legacy db.js `duplicateDetectionNote`).
    public let reason: String
    /// Underlying kind of match.
    public let kind: MatchKind

    public enum MatchKind: String, Sendable {
        case exactHash = "exact_hash"
        case similarHash = "similar_hash"
        /// Same applicant-tracking-system posting id extracted from the URL (TASK-620) — the same
        /// requisition captured from two URL forms/sources.
        case atsPostingID = "ats_posting_id"
        /// Byte-identical full source URL (query included) — the same posting captured twice, e.g. a
        /// levels.fyi SPA posting whose two DOM snapshots differ enough to dodge the exact-hash path
        /// (TASK-629).
        case sameURL = "same_url"
    }
}

/// Lightweight, Sendable snapshot of a job + its capture fields needed for dedup.
/// Avoids holding SwiftData model references across actor contexts.
public struct JobSnapshot: Sendable {
    public let id: String
    public let jobNumber: Int?
    public let company: String?
    public let title: String?
    public let location: String?
    public let remoteType: String?
    public let salaryMin: Int?
    public let salaryMax: Int?
    public let salaryCurrency: String?
    public let employmentType: String?
    public let seniority: String?
    public let status: String
    public let cleanedDescription: String?
    public let cleanedHash: String?
    /// Canonical (query-stripped) URL — the preferred display/source identifier.
    public let sourceURL: String
    /// The full captured URL including its query string. Unlike `sourceURL`, this keeps the query (e.g.
    /// levels.fyi `?…&jobId=…`) that pins a specific posting on SPA/aggregator pages — used only by the
    /// same-full-URL duplicate path (TASK-629).
    public let fullURL: String
    public let duplicateOfJobID: String?
    public let extractionStatus: String

    public init(job: Job, capture: Capture) {
        id = job.id
        jobNumber = job.jobNumber
        company = job.company
        title = job.title
        location = job.location
        remoteType = job.remoteType?.rawValue
        salaryMin = job.salaryMin
        salaryMax = job.salaryMax
        salaryCurrency = job.salaryCurrency
        employmentType = job.employmentType
        seniority = job.seniority
        status = job.status.rawValue
        cleanedDescription = capture.cleanedDescription
        cleanedHash = capture.cleanedHash
        sourceURL = capture.canonicalURL ?? capture.url
        fullURL = capture.url
        duplicateOfJobID = job.duplicateOfJobID
        extractionStatus = job.extractionStatus.rawValue
    }
}

// MARK: - DuplicateDetector

/// Pure duplicate-detection logic ported from server/db.js.
///
/// Call `duplicateGroups(context:)` to get UI-ready pairs.
/// Mutating the DB (setting duplicate_of_job_id) is the caller's responsibility
/// (e.g. JobService calls this after extraction, Duplicates screen calls this for the badge count).
public struct DuplicateDetector {
    public init() {}

    // MARK: - Shared review-count policy (TASK-581)

    /// Snapshots for duplicate *review*: only jobs not already marked `.duplicate` (those are
    /// resolved) and that have a capture. The single place the "what's reviewable" rule lives, shared
    /// by the Duplicates screen, the sidebar badge, and the dashboard card so they can't drift.
    public static func reviewSnapshots(jobs: [Job]) -> [JobSnapshot] {
        jobs.compactMap { job in
            // Only ACTIVE jobs are reviewable. Terminal statuses (already resolved as a duplicate, or
            // expired/rejected/passed/archived/closed) shouldn't form dedup pairs — an expired original
            // paired with a live candidate would push the user to mark the live job they're pursuing as
            // a dup of a dead posting (TASK-626, the Guild guild.com-vs-linkedin case).
            let excluded: Set<JobStatus> = [.duplicate, .expired, .rejected, .passed, .archived, .closed]
            guard !excluded.contains(job.status), let capture = job.capture else { return nil }
            return JobSnapshot(job: job, capture: capture)
        }
    }

    /// Count of unresolved duplicate-review pairs — the actionable number shown by the Duplicates
    /// screen, sidebar badge, and dashboard card. Excludes marked-`.duplicate` jobs (via
    /// `reviewSnapshots`) and pairs whose cleaned hash is already resolved by a `DuplicateDecision`.
    public static func unresolvedPairCount(jobs: [Job], decisions: [DuplicateDecision]) -> Int {
        let snapshots = reviewSnapshots(jobs: jobs)
        let resolvedHashes = Set(decisions.map(\.cleanedHash))
        return DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: resolvedHashes).count
    }

    // MARK: - Public API

    /// Returns all unresolved duplicate pairs for the UI, sorted by confidence descending.
    ///
    /// - Parameter context: A `ModelContext` to query from (may be main-actor or a background context).
    /// - Returns: Pairs whose cleaned hashes don't have a `DuplicateDecision` record.
    public func duplicateGroups(context: ModelContext) throws -> [DuplicatePair] {
        let snapshots = try fetchExtractedSnapshots(context: context)
        let decisions = try fetchDecisions(context: context)
        let resolvedHashes = Set(decisions.map(\.cleanedHash))
        return duplicateGroups(snapshots: snapshots, resolvedHashes: resolvedHashes)
    }

    /// Pure computation overload — use when snapshots and resolved hashes are already available
    /// (e.g. from @Query results). Safe to call from a background task.
    public func duplicateGroups(snapshots: [JobSnapshot], resolvedHashes: Set<String>) -> [DuplicatePair] {
        var pairs: [DuplicatePair] = []

        // 1. Exact hash groups (same cleaned_hash, multiple jobs, different URLs).
        //    Identical cleaned-description text is only a duplicate when the jobs plausibly
        //    belong to the same employer. Without this guard, generic/boilerplate descriptions
        //    that hash-collide across unrelated companies (e.g. Elastic vs Stripe) get flagged
        //    as 100% duplicates. Sub-cluster each hash group by company name and only pair jobs
        //    within the same company cluster.
        let snapshotsWithHash = snapshots.filter { $0.cleanedHash != nil }
        let hashGroups = Dictionary(grouping: snapshotsWithHash) { $0.cleanedHash ?? "" }
        for (hash, group) in hashGroups where group.count >= 2 {
            guard !resolvedHashes.contains(hash) else { continue }
            // Skip groups whose shared description carries too little signal. Short/boilerplate
            // text (e.g. a lone "$", a cookie banner, "Apply now") hash-collides across unrelated
            // postings and is not evidence of a genuine duplicate. Mirrors the >=8 meaningful-token
            // bar used by descriptionSimilarity in the heuristic path.
            let sharedText = group.first?.cleanedDescription ?? ""
            guard DuplicateDetector.descriptionTokens(sharedText).count >= 8 else { continue }
            for companyCluster in DuplicateDetector.clusterByCompany(group) where companyCluster.count >= 2 {
                // Sort by creation order proxy (jobNumber ascending = earlier capture = preferred)
                let sorted = companyCluster.sorted { ($0.jobNumber ?? Int.max) < ($1.jobNumber ?? Int.max) }
                let original = sorted[0]
                for candidate in sorted.dropFirst() {
                    pairs.append(DuplicatePair(
                        original: original,
                        candidate: candidate,
                        confidence: 1.0,
                        reason: "exact cleaned-description hash match",
                        kind: .exactHash
                    ))
                }
            }
        }

        // 1.5 Same ATS posting id (TASK-620): the same requisition captured from two URL forms/sources
        //     (e.g. Pinterest `/jobs/N/` vs `?gh_jid=N`, Workday `/details/` vs `/job/`, a LinkedIn
        //     search deep-link vs the posting view). The id is authoritative, so this pairs even when
        //     the titles or cleaned text differ — the highest-confidence, lowest-false-positive signal.
        let byATSID = Dictionary(grouping: snapshots.compactMap { snap -> (id: String, snap: JobSnapshot)? in
            guard let atsID = Self.atsPostingID(urlString: snap.sourceURL) else { return nil }
            return (atsID, snap)
        }) { $0.id }
        for (_, group) in byATSID where group.count >= 2 {
            let sorted = group.map(\.snap).sorted { ($0.jobNumber ?? Int.max) < ($1.jobNumber ?? Int.max) }
            let original = sorted[0]
            for candidate in sorted.dropFirst() {
                if let hash = candidate.cleanedHash, resolvedHashes.contains(hash) {
                    continue
                }
                pairs.append(DuplicatePair(
                    original: original, candidate: candidate, confidence: 1.0,
                    reason: "same ATS posting id in the source URL", kind: .atsPostingID
                ))
            }
        }

        // 1.7 Same specific full URL (TASK-629): two captures of the byte-identical posting URL (query
        //     included) — e.g. a levels.fyi SPA posting captured twice seconds apart, whose slightly
        //     different DOM snapshots dodge the exact-hash path. Definitive (same URL = same posting);
        //     gated on the URL carrying a query so generic query-less category/SPA pages don't collapse
        //     unrelated jobs (see `specificFullURLKey`).
        let bySpecificURL = Dictionary(grouping: snapshots.compactMap { snap -> (key: String, snap: JobSnapshot)? in
            guard let key = Self.specificFullURLKey(snap.fullURL) else { return nil }
            return (key, snap)
        }) { $0.key }
        for (_, group) in bySpecificURL where group.count >= 2 {
            let sorted = group.map(\.snap).sorted { ($0.jobNumber ?? Int.max) < ($1.jobNumber ?? Int.max) }
            let original = sorted[0]
            for candidate in sorted.dropFirst() {
                if let hash = candidate.cleanedHash, resolvedHashes.contains(hash) {
                    continue
                }
                pairs.append(DuplicatePair(
                    original: original, candidate: candidate, confidence: 1.0,
                    reason: "same source URL (captured twice)", kind: .sameURL
                ))
            }
        }

        // 2. Domain-heuristic duplicate detection (same algorithm as detectDomainDuplicateJobs in db.js)
        let heuristicPairs = detectDomainDuplicates(snapshots: snapshots, resolvedHashes: resolvedHashes)
        pairs.append(contentsOf: heuristicPairs)

        return collapseToOnePairPerCandidate(pairs)
    }

    /// Collapse to at most one pair per *candidate* job.
    ///
    /// Split from `duplicateGroups` for length: everything above FINDS candidate pairs by four
    /// different rules, and this decides which of them the user is actually shown.
    private func collapseToOnePairPerCandidate(_ pairs: [DuplicatePair]) -> [DuplicatePair] {
        // A star toward its best canonical, so N mutually-similar jobs yield N-1 review pairs rather
        // than every C(N,2) combination (TASK-620). Highest confidence wins (ATS id / exact hash
        // before the fuzzy heuristic); ties break deterministically by job number then id. The
        // unordered-pair guard also prevents A→B and B→A both appearing.
        let ordered = pairs.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            let leftOrig = lhs.original.jobNumber ?? Int.max
            let rightOrig = rhs.original.jobNumber ?? Int.max
            if leftOrig != rightOrig {
                return leftOrig < rightOrig
            }
            let leftCand = lhs.candidate.jobNumber ?? Int.max
            let rightCand = rhs.candidate.jobNumber ?? Int.max
            if leftCand != rightCand {
                return leftCand < rightCand
            }
            return lhs.candidate.id < rhs.candidate.id
        }
        var claimedCandidates = Set<String>()
        var seenUnordered = Set<String>()
        var deduped: [DuplicatePair] = []
        for pair in ordered {
            let unordered = [pair.original.id, pair.candidate.id].sorted().joined(separator: "||")
            if seenUnordered.contains(unordered) || claimedCandidates.contains(pair.candidate.id) {
                continue
            }
            seenUnordered.insert(unordered)
            claimedCandidates.insert(pair.candidate.id)
            deduped.append(pair)
        }
        return deduped
    }

    /// Incremental single-candidate check: returns the pair flagging `candidate` as a duplicate of an
    /// existing job, or nil. Reuses the exact batch matching logic (`duplicateGroups`) but only over
    /// the jobs that could possibly pair with the candidate — those sharing its normalized title or
    /// its cleaned hash — so it's cheap enough to run after each extraction (before fit scoring)
    /// instead of an O(N²) full rescan. Under the batch algorithm a candidate can only pair with a
    /// same-title (heuristic path) or same-cleaned-hash (exact path) job, so the scoped result is
    /// identical to what the full scan would produce for this candidate.
    public func duplicatePairForCandidate(
        _ candidate: JobSnapshot,
        among corpus: [JobSnapshot],
        resolvedHashes: Set<String>
    ) -> DuplicatePair? {
        // Any job that could pair with the candidate under the batch algorithm: same cleaned hash, same
        // ATS posting id, or a similar title (fuzzy). Same-company is enforced downstream by the batch
        // pass (TASK-620).
        let candATSID = Self.atsPostingID(urlString: candidate.sourceURL)
        let relevant = corpus.filter { snap in
            guard snap.id != candidate.id else { return false }
            if let hash = candidate.cleanedHash, snap.cleanedHash == hash {
                return true
            }
            if let candATSID, Self.atsPostingID(urlString: snap.sourceURL) == candATSID {
                return true
            }
            guard let title = snap.title, let candTitle = candidate.title else { return false }
            return Self.titlesAreSimilar(candTitle, title)
        }
        guard !relevant.isEmpty else { return nil }
        return duplicateGroups(snapshots: relevant + [candidate], resolvedHashes: resolvedHashes)
            .first { $0.candidate.id == candidate.id }
    }

    // MARK: - Hash helpers (matches capture pipeline)

    /// SHA-256 hex string of the cleaned description text.
    public static func cleanedHash(from cleanedDescription: String) -> String {
        sha256Hex(cleanedDescription)
    }

    /// SHA-256 hex string of the canonical capture payload (matches rawHash() in db.js).
    /// Keys must be sorted alphabetically: canonical_url, selected_text, structured_data, url, visible_text.
    public static func rawHash(
        url: String,
        canonicalURL: String?,
        selectedText: String?,
        visibleText: String?,
        structuredData: [[String: Any]]
    ) -> String {
        var payload: [String: Any] = [
            "url": url,
            "canonical_url": canonicalURL as Any,
            "selected_text": selectedText ?? "",
            "visible_text": visibleText ?? "",
            "structured_data": structuredData
        ]
        _ = payload // suppress warning; value is built below via sorted-key serialisation
        let json = sortedJSON([
            "canonical_url": canonicalURL as Any? ?? NSNull(),
            "selected_text": selectedText ?? "",
            "structured_data": structuredData,
            "url": url,
            "visible_text": visibleText ?? ""
        ])
        return sha256Hex(json)
    }

    // MARK: - Internal: text normalisation

    static func normalizeDuplicateText(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Work-arrangement qualifiers that show up as title suffixes (e.g. "… (Remote)") but don't
    /// distinguish the role. Kept deliberately tiny to avoid over-merging genuinely different titles.
    static let titleQualifierStopWords: Set<String> = ["remote", "hybrid", "onsite"]

    /// Common title-word abbreviations normalized so variants match (TASK-620).
    static let titleSynonyms: [String: String] = ["sr": "senior", "jr": "junior", "pgm": "program", "mgr": "manager"]

    /// Meaningful title tokens: normalized, work-arrangement qualifiers dropped, abbreviations expanded.
    static func titleTokens(_ title: String) -> Set<String> {
        Set(normalizeDuplicateText(title).split(separator: " ").map(String.init)
            .filter { !titleQualifierStopWords.contains($0) }
            .map { titleSynonyms[$0] ?? $0 })
    }

    /// Two titles match for the (recall-first) fuzzy grouping (TASK-620) when one's meaningful tokens
    /// are a subset of the other's — e.g. "Principal TPM" ⊆ "Principal TPM, Toast IQ" (an aggregator vs
    /// company-site variant) — or their Jaccard similarity clears `titleSimilarityThreshold`. Level
    /// words (senior/staff/principal) are kept, so different levels of the same role don't merge on the
    /// subset rule and only pair if the rest of the title is near-identical.
    static func titlesAreSimilar(_ lhs: String, _ rhs: String) -> Bool {
        let left = titleTokens(lhs)
        let right = titleTokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left.isSubset(of: right) || right.isSubset(of: left) {
            return true
        }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        return union > 0 && Double(intersection) / Double(union) >= titleSimilarityThreshold
    }

    // MARK: - Same-full-URL key (TASK-629)

    /// A normalized key for the same-full-URL duplicate path: host lowercased, query items sorted,
    /// fragment and trailing slash stripped. Returns nil unless the URL carries a query string — the
    /// query is what pins a specific posting on SPA/aggregator pages (e.g. levels.fyi
    /// `…/technical-program-manager?…&jobId=119…`), whereas the query-less path there is a generic
    /// category page shared by many different jobs. Query-less per-posting URLs (Greenhouse
    /// `/jobs/7944159`, LinkedIn `/jobs/view/N`) are already covered by the ATS-posting-id path, so
    /// requiring a query here loses nothing while preventing generic pages from collapsing unrelated jobs.
    static func specificFullURLKey(_ urlString: String) -> String? {
        guard var comps = URLComponents(string: urlString),
              let host = comps.host, !host.isEmpty,
              let items = comps.queryItems, !items.isEmpty else { return nil }
        comps.host = host.lowercased()
        comps.fragment = nil
        comps.queryItems = items.sorted {
            $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name
        }
        var path = comps.path
        while path.hasSuffix("/"), path.count > 1 {
            path = String(path.dropLast())
        }
        comps.path = path
        return comps.url?.absoluteString ?? comps.string
    }

    // MARK: - ATS posting-id extraction (TASK-620)

    /// Applicant-tracking-system registrable hosts whose URLs carry a stable posting id, plus company
    /// career sites that expose Greenhouse's `gh_jid`. Used only to note when an id was found.
    static func atsPostingID(urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString), let host = comps.host?.lowercased() else { return nil }
        let items = comps.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name.lowercased() }?.value
        }
        let path = comps.path

        // Greenhouse `gh_jid` — globally unique, and exposed by many company career sites (Pinterest,
        // Stripe, Toast, GFiber, Motional, Cribl, Five9, …) as well as job-boards.greenhouse.io.
        if let ghjid = query("gh_jid"), !ghjid.isEmpty, ghjid.allSatisfy(\.isNumber) {
            return "gh:\(ghjid)"
        }
        if ATSHost.belongs(host, to: "greenhouse.io"),
           let id = trailingNumericID(in: path, after: "jobs") {
            return "gh:\(id)"
        }
        // LinkedIn — /jobs/view/N and search ?currentJobId=N are the same posting.
        if ATSHost.belongs(host, to: "linkedin.com") {
            if let id = query("currentJobId"), !id.isEmpty, id.allSatisfy(\.isNumber) {
                return "li:\(id)"
            }
            if let id = trailingNumericID(in: path, after: "view") {
                return "li:\(id)"
            }
        }
        // Workday — req id is only tenant-unique, so key by tenant (the host's first label) + req.
        if ATSHost.belongs(host, to: "myworkdayjobs.com"), let reqID = workdayReqID(fromPath: path) {
            let tenant = host.split(separator: ".").first.map(String.init) ?? ""
            return "wd:\(tenant):\(reqID)"
        }
        // Ashby / Lever — /{company}/{uuid}; uuid is unique but qualify with company for safety.
        if ATSHost.belongs(host, to: "ashbyhq.com"), let key = firstTwoPathSegments(path) {
            return "ashby:\(key)"
        }
        if ATSHost.belongs(host, to: "lever.co"), let key = firstTwoPathSegments(path) {
            return "lever:\(key)"
        }
        return nil
    }

    private static func trailingNumericID(in path: String, after marker: String) -> String? {
        let segments = path.split(separator: "/").map(String.init)
        guard let idx = segments.firstIndex(of: marker), idx + 1 < segments.count else { return nil }
        let candidate = segments[idx + 1]
        return candidate.allSatisfy(\.isNumber) && !candidate.isEmpty ? candidate : nil
    }

    private static func firstTwoPathSegments(_ path: String) -> String? {
        let segments = path.split(separator: "/").map(String.init)
        guard segments.count >= 2 else { return nil }
        return "\(segments[0]):\(segments[1])"
    }

    /// Workday requisition id (`…_P750335-1` → `P750335`), tolerant of both `/job/` and `/details/`
    /// URL shapes. Strips the trailing `-N` posting index so index variants of one req match.
    static func workdayReqID(fromPath path: String) -> String? {
        guard let last = path.split(separator: "/").last.map(String.init),
              let underscore = last.lastIndex(of: "_") else { return nil }
        var reqID = String(last[last.index(after: underscore)...])
        if let dash = reqID.range(of: #"-\d+$"#, options: .regularExpression) {
            reqID.removeSubrange(dash)
        }
        return reqID.isEmpty ? nil : reqID
    }

    // MARK: - Tuning constants (heuristic — see docs/tuning.md)

    //
    // The duplicate-confidence score is a hand-tuned formula. These name its magic numbers so the
    // computation in `duplicateGroups` reads intelligibly and can be adjusted in one place. Values are
    // unchanged from the previous inline literals — behavior is identical.

    /// Base confidence for a same-domain duplicate, before description/field adjustments.
    static let baseDomainConfidence = 0.65
    /// How much the keep-vs-candidate domain-score gap (0–100) widens confidence.
    static let rankSpreadWeight = 0.24
    /// Token count at which description-similarity evidence reaches full weight.
    static let descFullWeightTokens = 30.0
    /// Scale applied to (similarity − midpoint) when adjusting confidence.
    static let descAdjustmentScale = 0.3
    /// Similarity midpoint — above it raises confidence, below it lowers it.
    static let descSimilarityMidpoint = 0.5
    /// Confidence subtracted per conflicting field (remote / seniority / location / currency).
    static let fieldConflictPenalty = 0.08
    /// Confidence clamp bounds.
    static let confidenceFloor = 0.01
    static let confidenceCeiling = 0.99
    /// Salary bands diverging beyond this fraction on BOTH bounds hard-block a match.
    static let salaryDivergenceThreshold = 0.1
    /// Default company-name Jaccard similarity to cluster two jobs as the same company.
    static let companyClusterThreshold = 0.5
    /// Title-token Jaccard at/above which two titles in the same company are treated as the same role
    /// for the fuzzy grouping (TASK-620). Recall-first: lower = more candidate pairs surfaced for
    /// review. The subset rule catches suffix variants regardless of this threshold.
    static let titleSimilarityThreshold = 0.6

    /// Tokens that carry no signal for company identity (matches db.js COMPANY_STOP_WORDS).
    /// Extend this list as new noise words surface — see docs/tuning.md.
    static let companyStopWords: Set<String> = [
        "the", "a", "an", "of", "for", "and", "or", "in", "at", "by", "to", "its", "with",
        "inc", "corp", "corporation", "co", "ltd", "llc", "llp", "lp", "plc",
        "technologies", "technology", "tech", "group", "holdings", "holding",
        "solutions", "services", "systems", "software", "platforms", "platform",
        "global", "international", "worldwide", "ventures", "labs", "lab", "ai"
    ]

    static func companyTokens(_ name: String) -> Set<String> {
        Set(normalizeDuplicateText(name).split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !companyStopWords.contains($0) })
    }

    /// Jaccard similarity on meaningful company name tokens.
    static func companyJaccard(_ compA: String, _ compB: String) -> Double {
        let tokensA = companyTokens(compA)
        let tokensB = companyTokens(compB)
        if tokensA.isEmpty && tokensB.isEmpty {
            return 1.0
        }
        if tokensA.isEmpty || tokensB.isEmpty {
            return 0.0
        }
        let intersection = tokensA.intersection(tokensB).count
        let union = tokensA.union(tokensB).count
        return Double(intersection) / Double(union)
    }

    // MARK: - Internal: description similarity (matches duplicateDescriptionSimilarity in db.js)

    /// Common job-posting boilerplate words that carry no signal for description similarity.
    /// Extend as new boilerplate surfaces — see docs/tuning.md.
    static let descriptionStopWords: Set<String> = [
        "about", "above", "across", "after", "again", "against", "also", "and", "another", "apply",
        "because", "been", "before", "being", "benefits", "between", "candidate", "careers", "company",
        "could", "description", "each", "employment", "equal", "every", "from", "have", "hiring",
        "into", "including", "jobs", "listed", "looking", "more", "must", "other", "over", "position",
        "posted", "posting", "remote", "requirements", "responsibilities", "role", "same", "seeking",
        "should", "team", "than", "that", "their", "there", "this", "through", "with", "will", "work",
        "working", "would", "years", "your"
    ]

    static func descriptionTokens(_ value: String) -> Set<String> {
        Set(normalizeDuplicateText(value).split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 4 && !descriptionStopWords.contains($0) })
    }

    /// Returns nil if either side has < 8 meaningful tokens (not enough signal).
    static func descriptionSimilarity(left: String?, right: String?) -> (similarity: Double, tokenCount: Int)? {
        let leftTokens = descriptionTokens(left ?? "")
        let rightTokens = descriptionTokens(right ?? "")
        let smaller = min(leftTokens.count, rightTokens.count)
        guard smaller >= 8 else { return nil }
        let intersection = leftTokens.intersection(rightTokens).count
        return (Double(intersection) / Double(smaller), smaller)
    }

    // MARK: - Internal: domain score (matches companyDomainScore in db.js)

    static let atsRegistrables: Set<String> = [
        "greenhouse", "lever", "workday", "myworkdayjobs", "ashbyhq", "smartrecruiters",
        "taleo", "icims", "bamboohr", "jobvite", "recruitee", "workable", "rippling",
        "pinpointhq", "dover", "jazhr", "breezy", "jobscore", "applytojob"
    ]

    static func companyDomainScore(company: String?, urlString: String) -> Int {
        guard let company, !company.isEmpty else { return 0 }
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return 0 }
        let hostname = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let companyText = normalizeDuplicateText(company)
        let companyCompact = companyText.replacingOccurrences(of: " ", with: "")
        guard !companyCompact.isEmpty else { return 0 }

        let labels = hostname.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        let registrable = labels.count >= 2 ? labels[labels.count - 2] : labels.first ?? ""
        let hostCompact = labels.joined()

        if registrable == companyCompact {
            return 100
        }
        if labels.contains(companyCompact) {
            return 90
        }
        if hostCompact == companyCompact {
            return 85
        }
        if companyCompact.count >= 4 && labels.contains(where: { $0.contains(companyCompact) }) {
            return 70
        }
        if companyCompact.count >= 4 && hostCompact.contains(companyCompact) {
            return 60
        }

        let companyWords = companyText.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        if !companyWords.isEmpty && companyWords.contains(where: { labels.contains($0) }) {
            return 50
        }

        if atsRegistrables.contains(registrable) {
            return 45
        }
        return 0
    }

    static func sourceHostname(urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Internal: evidence matching (matches duplicateEvidenceMatch in db.js)

    struct Evidence {
        var descSimilarity: Double?
        var descTokenCount: Int
        var fieldConflicts: [String]
    }

    static func knownValue(_ value: String?) -> String {
        let normalized = normalizeDuplicateText(value ?? "")
        return (normalized.isEmpty || normalized == "unknown") ? "" : normalized
    }

    /// Returns nil if salary bands diverge > 10% on both bounds (hard block).
    static func evidenceMatch(left: JobSnapshot, right: JobSnapshot) -> Evidence? {
        // Hard block: salary divergence
        if let lMin = left.salaryMin, let rMin = right.salaryMin,
           let lMax = left.salaryMax, let rMax = right.salaryMax {
            let minDiff = Double(abs(lMin - rMin)) / Double(max(lMin, rMin))
            let maxDiff = Double(abs(lMax - rMax)) / Double(max(lMax, rMax))
            if minDiff > salaryDivergenceThreshold && maxDiff > salaryDivergenceThreshold {
                return nil
            }
        }

        var fieldConflicts: [String] = []
        for (field, leftVal, rightVal) in [
            ("remote_type", left.remoteType, right.remoteType),
            ("employment_type", left.employmentType, right.employmentType),
            ("seniority", left.seniority, right.seniority),
            ("location", left.location, right.location)
        ] as [(String, String?, String?)] {
            let leftKnown = knownValue(leftVal)
            let rightKnown = knownValue(rightVal)
            if !leftKnown.isEmpty && !rightKnown.isEmpty && leftKnown != rightKnown {
                fieldConflicts.append(field)
            }
        }
        if let leftCurrency = left.salaryCurrency, let rightCurrency = right.salaryCurrency,
           leftCurrency != rightCurrency {
            fieldConflicts.append("salary_currency")
        }

        let simResult = descriptionSimilarity(left: left.cleanedDescription, right: right.cleanedDescription)
        return Evidence(
            descSimilarity: simResult?.similarity,
            descTokenCount: simResult?.tokenCount ?? 0,
            fieldConflicts: fieldConflicts
        )
    }

    // MARK: - Internal: union-find company clustering (matches clusterByCompany in db.js)

    static func clusterByCompany(
        _ jobs: [JobSnapshot],
        threshold: Double = companyClusterThreshold
    ) -> [[JobSnapshot]] {
        let count = jobs.count
        var parent = Array(0 ..< count)
        func find(_ nodeIdx: Int) -> Int {
            var nodeIdx = nodeIdx
            while parent[nodeIdx] != nodeIdx {
                parent[nodeIdx] = parent[parent[nodeIdx]]
                nodeIdx = parent[nodeIdx]
            }
            return nodeIdx
        }
        for idx in 0 ..< count {
            for jdx in (idx + 1) ..< count
                where companyJaccard(jobs[idx].company ?? "", jobs[jdx].company ?? "") >= threshold {
                let parentI = find(idx), parentJ = find(jdx)
                if parentI != parentJ {
                    parent[parentI] = parentJ
                }
            }
        }
        var clusters: [Int: [JobSnapshot]] = [:]
        for idx in 0 ..< count {
            let root = find(idx)
            clusters[root, default: []].append(jobs[idx])
        }
        return Array(clusters.values)
    }

    // MARK: - Internal: domain-heuristic duplicate detection (matches detectDomainDuplicateJobs in db.js)

    func detectDomainDuplicates(snapshots: [JobSnapshot], resolvedHashes: Set<String>) -> [DuplicatePair] {
        let active = snapshots.filter {
            $0.extractionStatus == "succeeded" &&
                !($0.company?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) &&
                !($0.title?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) &&
                !["passed", "archived", "closed", "expired", "rejected"].contains($0.status) &&
                // Exclude already-resolved duplicates (either signal suffices per invariant).
                $0.duplicateOfJobID == nil &&
                $0.status != "duplicate"
        }

        // TASK-620 (recall-first): cluster ALL active jobs by company, then compare every same-company
        // pair whose titles are *similar* (fuzzy, not exact) — regardless of hostname, so same-site URL
        // variants and aggregator-vs-company-site captures are both compared. The exact-title grouping
        // and the two-distinct-hostname requirement are gone; the company clustering, title similarity,
        // and evidence scoring are what guard against unrelated pairs.
        var pairs: [DuplicatePair] = []
        for cluster in DuplicateDetector.clusterByCompany(active) where cluster.count >= 2 {
            let scored = cluster.map { snap -> (snap: JobSnapshot, score: Int) in
                (snap, DuplicateDetector.companyDomainScore(company: snap.company, urlString: snap.sourceURL))
            }
            for lhsIdx in 0 ..< scored.count {
                for rhsIdx in (lhsIdx + 1) ..< scored.count {
                    guard let pair = domainPair(scored[lhsIdx], scored[rhsIdx], resolvedHashes: resolvedHashes) else {
                        continue
                    }
                    pairs.append(pair)
                }
            }
        }
        return pairs
    }

    /// Evaluate one same-company job pair for the fuzzy domain-heuristic path (TASK-620). Returns a
    /// `DuplicatePair` when the titles are similar, evidence doesn't hard-block, and neither side is
    /// resolved; the higher domain-authority source is kept as canonical (ties broken by job number).
    private func domainPair(
        _ lhs: (snap: JobSnapshot, score: Int),
        _ rhs: (snap: JobSnapshot, score: Int),
        resolvedHashes: Set<String>
    ) -> DuplicatePair? {
        guard let leftTitle = lhs.snap.title, let rightTitle = rhs.snap.title,
              DuplicateDetector.titlesAreSimilar(leftTitle, rightTitle) else { return nil }

        // Keep = higher domain score; tie → lower job number (earlier capture) is canonical.
        let keepPair: (snap: JobSnapshot, score: Int)
        let candPair: (snap: JobSnapshot, score: Int)
        if lhs.score != rhs.score {
            (keepPair, candPair) = lhs.score > rhs.score ? (lhs, rhs) : (rhs, lhs)
        } else {
            let lhsFirst = (lhs.snap.jobNumber ?? Int.max) <= (rhs.snap.jobNumber ?? Int.max)
            (keepPair, candPair) = lhsFirst ? (lhs, rhs) : (rhs, lhs)
        }
        let keep = keepPair.snap
        let candidate = candPair.snap

        guard ["new", "pursuing", "duplicate", "applied"].contains(candidate.status) else { return nil }
        guard let evidence = DuplicateDetector.evidenceMatch(left: keep, right: candidate) else { return nil }
        if let hash = candidate.cleanedHash, resolvedHashes.contains(hash) {
            return nil
        }
        if let hash = keep.cleanedHash, resolvedHashes.contains(hash) {
            return nil
        }

        let domainConfidence = Self.baseDomainConfidence
            + (Double(keepPair.score - candPair.score) / 100.0) * Self.rankSpreadWeight
        let descWeight = evidence.descSimilarity == nil ? 0.0
            : min(1.0, Double(evidence.descTokenCount) / Self.descFullWeightTokens)
        let descAdj: Double = if let sim = evidence.descSimilarity {
            descWeight * (sim - Self.descSimilarityMidpoint) * Self.descAdjustmentScale
        } else {
            0.0
        }
        let fieldPenalty = Double(evidence.fieldConflicts.count) * Self.fieldConflictPenalty
        let confidence = min(
            Self.confidenceCeiling,
            max(Self.confidenceFloor, domainConfidence + descAdj - fieldPenalty)
        )

        let keepHost = DuplicateDetector.sourceHostname(urlString: keep.sourceURL)
        let candHost = DuplicateDetector.sourceHostname(urlString: candidate.sourceURL)
        var reasonParts = keepHost == candHost
            ? ["same company + similar title on \(keepHost.isEmpty ? "the same source" : keepHost)"]
            : ["preferred \(keepHost) over \(candHost)"]
        if let sim = evidence.descSimilarity {
            reasonParts
                .append("description similarity \(String(format: "%.2f", sim)) (\(evidence.descTokenCount) tokens)")
        }
        if !evidence.fieldConflicts.isEmpty {
            reasonParts.append("field conflicts: \(evidence.fieldConflicts.joined(separator: ", "))")
        }

        return DuplicatePair(
            original: keep, candidate: candidate, confidence: confidence,
            reason: reasonParts.joined(separator: "; "), kind: .similarHash
        )
    }

    // MARK: - Internal: DB queries

    private func fetchExtractedSnapshots(context: ModelContext) throws -> [JobSnapshot] {
        let descriptor = FetchDescriptor<Job>()
        let jobs = try context.fetch(descriptor)
        return jobs.compactMap { job -> JobSnapshot? in
            guard let capture = job.capture else { return nil }
            return JobSnapshot(job: job, capture: capture)
        }
    }

    private func fetchDecisions(context: ModelContext) throws -> [DuplicateDecision] {
        try context.fetch(FetchDescriptor<DuplicateDecision>())
    }

    // MARK: - Internal: crypto / JSON helpers

    static func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Produces compact JSON with keys sorted (matches db.js sortedJson + Python json.dumps sort_keys=True).
    static func sortedJSON(_ value: Any) -> String {
        switch value {
        case let arr as [Any]:
            let items = arr.map { sortedJSON($0) }.joined(separator: ",")
            return "[\(items)]"
        case let dict as [String: Any]:
            let pairs = dict.keys.sorted().map { key -> String in
                let jsonKey = jsonString(key)
                let val = dict[key] ?? NSNull()
                return "\(jsonKey):\(sortedJSON(val))"
            }.joined(separator: ",")
            return "{\(pairs)}"
        case is NSNull:
            return "null"
        case let boolVal as Bool:
            return boolVal ? "true" : "false"
        case let intVal as Int:
            return "\(intVal)"
        case let doubleVal as Double:
            // Guarded conversion: `Int(Double)` traps (aborts the process) for values outside Int range
            // or non-finite, and this runs on attacker-controlled JSON-LD numbers (e.g. 1e19). Fall back
            // to the double formatting when the value can't be represented as an Int (CWE-190).
            if doubleVal.truncatingRemainder(dividingBy: 1) == 0, let intVal = Int(exactly: doubleVal) {
                return "\(intVal)"
            }
            return "\(doubleVal)"
        case let strVal as String:
            return jsonString(strVal)
        default:
            return "null"
        }
    }

    private static func jsonString(_ str: String) -> String {
        var result = "\""
        for scalar in str.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0x00 ..< 0x20:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}

// swiftlint:enable file_length type_body_length large_tuple
