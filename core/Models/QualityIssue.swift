import Foundation

// MARK: - QualityIssueKind

public enum QualityIssueKind: String, CaseIterable, Sendable {
    case missingCompany
    case missingTitle
    case missingLocation
    case missingWorkMode
    case missingSalary
    case extractionFailed
    case extractionPending
    case shortRawText // <1000B raw text
    case shortCleanedText // <700B cleaned text
    case staleExtraction // >21 days since extraction

    public var label: String {
        switch self {
        case .missingCompany: "Missing company"
        case .missingTitle: "Missing title"
        case .missingLocation: "Missing location"
        case .missingWorkMode: "Missing work mode"
        case .missingSalary: "Missing salary"
        case .extractionFailed: "Extraction failed"
        case .extractionPending: "Extraction pending"
        case .shortRawText: "Short capture"
        case .shortCleanedText: "Short cleaned text"
        case .staleExtraction: "Stale extraction"
        }
    }

    public var isHighSeverity: Bool {
        switch self {
        case .missingCompany, .missingTitle, .missingLocation, .extractionFailed:
            true
        default:
            false
        }
    }
}

// MARK: - QualityIssue

public struct QualityIssue: Identifiable, Sendable {
    public let id: UUID
    public let jobID: String
    public let kinds: [QualityIssueKind]
    public var severity: Int {
        kinds.count
    }

    /// True when any of this job's issue kinds is itself high-severity (TASK-458) — distinct from
    /// "has many issues". Use this for high-severity reporting, not a raw issue count.
    public var isHighSeverity: Bool {
        kinds.contains { $0.isHighSeverity }
    }

    public init(jobID: String, kinds: [QualityIssueKind]) {
        id = UUID()
        self.jobID = jobID
        self.kinds = kinds
    }
}

// MARK: - QualityChecker

public enum QualityChecker: Sendable {
    private static let staleThresholdDays = 21
    private static let minRawBytes = 1000
    private static let minCleanedBytes = 700

    // swiftlint:disable:next cyclomatic_complexity
    public static func issues(for job: Job) -> [QualityIssueKind] {
        var kinds: [QualityIssueKind] = []

        // TASK-459: while extraction is still pending, the extracted fields are EXPECTED to be
        // missing — those gaps aren't real data-quality defects yet. Suppress the missing-extracted-
        // field issues (company/title/location/work mode/salary) in the pending state; capture-size
        // issues below are about the input and still apply.
        let extractionPending = job.extractionStatus == .pending
        if !extractionPending {
            // Missing core fields
            if !hasValue(job.company) { kinds.append(.missingCompany) }
            if !hasValue(job.title) { kinds.append(.missingTitle) }
            if !hasValue(job.location) { kinds.append(.missingLocation) }

            // Work mode: unknown counts as missing
            if job.remoteType == nil || job.remoteType == .unknown {
                kinds.append(.missingWorkMode)
            }

            // Salary: missing if no min, max, or note
            if job.salaryMin == nil && job.salaryMax == nil && !hasValue(job.salaryNote) {
                kinds.append(.missingSalary)
            }
        }

        // Extraction status
        if job.extractionStatus == .failed { kinds.append(.extractionFailed) }
        if job.extractionStatus == .pending { kinds.append(.extractionPending) }

        // Raw text size
        let rawSize = rawByteSize(job)
        if rawSize < minRawBytes { kinds.append(.shortRawText) }

        // Cleaned text size
        let cleanedSize = cleanedByteSize(job)
        if cleanedSize < minCleanedBytes { kinds.append(.shortCleanedText) }

        // Stale extraction
        if let extractedAt = job.extractedAt {
            let daysSince = Calendar.current.dateComponents([.day], from: extractedAt, to: Date()).day ?? 0
            if daysSince > staleThresholdDays { kinds.append(.staleExtraction) }
        }

        return kinds
    }

    public static func issuesForAllJobs(_ jobs: [Job]) -> [QualityIssue] {
        jobs.compactMap { job in
            let kinds = issues(for: job)
            guard !kinds.isEmpty else { return nil }
            return QualityIssue(jobID: job.id, kinds: kinds)
        }
    }

    // MARK: - Private helpers

    private static func hasValue(_ value: String?) -> Bool {
        guard let v = value else { return false }
        let trimmed = v.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != "—" && trimmed.lowercased() != "unknown"
    }

    /// Total raw bytes captured = selected + visible (TASK-445). Matches the value stored at ingest;
    /// the `.shortRawText` check asks "did the capture transmit enough raw text", so it counts the
    /// full transmitted input rather than `max`, which undercounted captures where both contribute.
    /// (Deduped unique content is the separate `cleanedTextBytes` / `.shortCleanedText` check.)
    private static func rawByteSize(_ job: Job) -> Int {
        if let cached = job.rawTextBytes { return cached }
        let selected = job.capture?.selectedText?.utf8.count ?? 0
        let visible = job.capture?.visibleText?.utf8.count ?? 0
        return selected + visible
    }

    private static func cleanedByteSize(_ job: Job) -> Int {
        if let cached = job.cleanedTextBytes { return cached }
        return job.capture?.cleanedDescription?.utf8.count ?? 0
    }
}
