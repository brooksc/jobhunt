// swiftlint:disable line_length cyclomatic_complexity function_body_length type_body_length large_tuple
import Foundation
import CryptoKit
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
    public let sourceURL: String
    public let duplicateOfJobID: String?
    public let extractionStatus: String

    init(job: Job, capture: Capture) {
        self.id = job.id
        self.jobNumber = job.jobNumber
        self.company = job.company
        self.title = job.title
        self.location = job.location
        self.remoteType = job.remoteType?.rawValue
        self.salaryMin = job.salaryMin
        self.salaryMax = job.salaryMax
        self.salaryCurrency = job.salaryCurrency
        self.employmentType = job.employmentType
        self.seniority = job.seniority
        self.status = job.status.rawValue
        self.cleanedDescription = capture.cleanedDescription
        self.cleanedHash = capture.cleanedHash
        self.sourceURL = capture.canonicalURL ?? capture.url
        self.duplicateOfJobID = job.duplicateOfJobID
        self.extractionStatus = job.extractionStatus.rawValue
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

    // MARK: - Public API

    /// Returns all unresolved duplicate pairs for the UI, sorted by confidence descending.
    ///
    /// - Parameter context: A `ModelContext` to query from (may be main-actor or a background context).
    /// - Returns: Pairs whose cleaned hashes don't have a `DuplicateDecision` record.
    public func duplicateGroups(context: ModelContext) throws -> [DuplicatePair] {
        let snapshots = try fetchExtractedSnapshots(context: context)
        let decisions = try fetchDecisions(context: context)
        let resolvedHashes = Set(decisions.map(\.cleanedHash))

        var pairs: [DuplicatePair] = []

        // 1. Exact hash groups (same cleaned_hash, multiple jobs, different URLs)
        let snapshotsWithHash = snapshots.filter { $0.cleanedHash != nil }
        let hashGroups = Dictionary(grouping: snapshotsWithHash) { $0.cleanedHash ?? "" }
        for (hash, group) in hashGroups where group.count >= 2 {
            guard !resolvedHashes.contains(hash) else { continue }
            // Sort by creation order proxy (jobNumber ascending = earlier capture = preferred)
            let sorted = group.sorted { ($0.jobNumber ?? Int.max) < ($1.jobNumber ?? Int.max) }
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

        // 2. Domain-heuristic duplicate detection (same algorithm as detectDomainDuplicateJobs in db.js)
        let heuristicPairs = detectDomainDuplicates(snapshots: snapshots, resolvedHashes: resolvedHashes)
        pairs.append(contentsOf: heuristicPairs)

        // Deduplicate: prefer exact_hash pair if both kinds appear for the same (original, candidate)
        var seen = Set<String>()
        var deduped: [DuplicatePair] = []
        for pair in pairs.sorted(by: { $0.confidence > $1.confidence }) {
            let key = "\(pair.original.id)||\(pair.candidate.id)"
            let reverseKey = "\(pair.candidate.id)||\(pair.original.id)"
            if seen.contains(key) || seen.contains(reverseKey) { continue }
            seen.insert(key)
            deduped.append(pair)
        }

        return deduped
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

    // Tokens that carry no signal for company identity (matches db.js COMPANY_STOP_WORDS)
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
        if tokensA.isEmpty && tokensB.isEmpty { return 1.0 }
        if tokensA.isEmpty || tokensB.isEmpty { return 0.0 }
        let intersection = tokensA.intersection(tokensB).count
        let union = tokensA.union(tokensB).count
        return Double(intersection) / Double(union)
    }

    // MARK: - Internal: description similarity (matches duplicateDescriptionSimilarity in db.js)

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

        if registrable == companyCompact { return 100 }
        if labels.contains(companyCompact) { return 90 }
        if hostCompact == companyCompact { return 85 }
        if companyCompact.count >= 4 && labels.contains(where: { $0.contains(companyCompact) }) { return 70 }
        if companyCompact.count >= 4 && hostCompact.contains(companyCompact) { return 60 }

        let companyWords = companyText.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        if !companyWords.isEmpty && companyWords.contains(where: { labels.contains($0) }) { return 50 }

        if atsRegistrables.contains(registrable) { return 45 }
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
            if minDiff > 0.1 && maxDiff > 0.1 { return nil }
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
            if !leftKnown.isEmpty && !rightKnown.isEmpty && leftKnown != rightKnown { fieldConflicts.append(field) }
        }
        if let leftCurrency = left.salaryCurrency, let rightCurrency = right.salaryCurrency, leftCurrency != rightCurrency {
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

    static func clusterByCompany(_ jobs: [JobSnapshot], threshold: Double = 0.5) -> [[JobSnapshot]] {
        let count = jobs.count
        var parent = Array(0..<count)
        func find(_ nodeIdx: Int) -> Int {
            var nodeIdx = nodeIdx
            while parent[nodeIdx] != nodeIdx {
                parent[nodeIdx] = parent[parent[nodeIdx]]
                nodeIdx = parent[nodeIdx]
            }
            return nodeIdx
        }
        for idx in 0..<count {
            for jdx in (idx+1)..<count where companyJaccard(jobs[idx].company ?? "", jobs[jdx].company ?? "") >= threshold {
                let parentI = find(idx), parentJ = find(jdx)
                if parentI != parentJ { parent[parentI] = parentJ }
            }
        }
        var clusters: [Int: [JobSnapshot]] = [:]
        for idx in 0..<count {
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
            !["archived", "not_available"].contains($0.status)
        }

        // Group by normalised title
        var byTitle: [String: [JobSnapshot]] = [:]
        for snap in active {
            guard let title = snap.title, !title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let key = DuplicateDetector.normalizeDuplicateText(title)
            guard !key.isEmpty else { continue }
            byTitle[key, default: []].append(snap)
        }

        var pairs: [DuplicatePair] = []

        for titleGroup in byTitle.values where titleGroup.count >= 2 {
            for cluster in DuplicateDetector.clusterByCompany(titleGroup) where cluster.count >= 2 {
                let hostnames = Set(cluster.map { DuplicateDetector.sourceHostname(urlString: $0.sourceURL) }.filter { !$0.isEmpty })
                guard hostnames.count >= 2 else { continue }

                // Sort by domain score desc, then id asc (stable tie-break)
                let sorted = cluster
                    .map { snap -> (snap: JobSnapshot, score: Int) in
                        (snap, DuplicateDetector.companyDomainScore(company: snap.company, urlString: snap.sourceURL))
                    }
                    .sorted { lhs, rhs in
                        if lhs.score != rhs.score { return lhs.score > rhs.score }
                        return lhs.snap.id < rhs.snap.id
                    }

                let (keep, keepScore) = (sorted[0].snap, sorted[0].score)
                let runnerUpScore = sorted[1].score
                guard keepScore > 0 && keepScore != runnerUpScore else { continue }

                let keepHostname = DuplicateDetector.sourceHostname(urlString: keep.sourceURL)

                for (candidate, candidateScore) in sorted.dropFirst() {
                    guard ["saved", "duplicate", "applied"].contains(candidate.status) else { continue }
                    guard let evidence = DuplicateDetector.evidenceMatch(left: keep, right: candidate) else { continue }

                    // Skip if resolved by DuplicateDecision
                    if let hash = candidate.cleanedHash, resolvedHashes.contains(hash) { continue }
                    if let hash = keep.cleanedHash, resolvedHashes.contains(hash) { continue }

                    let domainConfidence = 0.65 + (Double(keepScore - candidateScore) / 100.0) * 0.24
                    let descWeight = evidence.descSimilarity == nil ? 0.0
                        : min(1.0, Double(evidence.descTokenCount) / 30.0)
                    let descAdj: Double
                    if let sim = evidence.descSimilarity {
                        descAdj = descWeight * (sim - 0.5) * 0.3
                    } else {
                        descAdj = 0.0
                    }
                    let fieldPenalty = Double(evidence.fieldConflicts.count) * 0.08
                    let confidence = min(0.99, max(0.01, domainConfidence + descAdj - fieldPenalty))

                    let candidateHostname = DuplicateDetector.sourceHostname(urlString: candidate.sourceURL)
                    var reasonParts = ["preferred \(keepHostname) over \(candidateHostname)"]
                    if let sim = evidence.descSimilarity {
                        reasonParts.append("description similarity \(String(format: "%.2f", sim)) (\(evidence.descTokenCount) tokens)")
                    }
                    if !evidence.fieldConflicts.isEmpty {
                        reasonParts.append("field conflicts: \(evidence.fieldConflicts.joined(separator: ", "))")
                    }

                    pairs.append(DuplicatePair(
                        original: keep,
                        candidate: candidate,
                        confidence: confidence,
                        reason: reasonParts.joined(separator: "; "),
                        kind: .similarHash
                    ))
                }
            }
        }

        return pairs
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
            if doubleVal.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(doubleVal))" }
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
            case 0x00..<0x20:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}
// swiftlint:enable line_length cyclomatic_complexity function_body_length type_body_length large_tuple
