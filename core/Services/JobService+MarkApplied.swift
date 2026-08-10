import Foundation
import SwiftData

// MARK: - Mark applied by URL (TASK-618)

/// Split out of `JobService.swift` to keep that file within the project's length limits.
extension JobService {
    // MARK: - Mark applied by URL (TASK-618)

    /// The outcome of `markJobApplied`, shaped for the MCP structured response.
    public struct MarkAppliedResult: Sendable {
        public let jobID: String
        public let jobNumber: Int?
        public let company: String?
        public let title: String?
        public let previousStatus: String
        public let status: String
        /// A new minimal job was created because nothing matched the URL.
        public let created: Bool
        /// The job was already Applied — a successful idempotent no-op.
        public let alreadyApplied: Bool
        /// The job is past Applied (Interview/Offer); it was deliberately NOT regressed.
        public let laterStage: Bool
        public let matchedURL: String?
        public let appliedAt: Date?
    }

    public enum MarkAppliedError: Error, LocalizedError {
        case ambiguous(matches: [Int])
        case invalidURL(String)

        public var errorDescription: String? {
            switch self {
            case let .ambiguous(matches):
                "This URL matches multiple jobs (\(matches.map(String.init).joined(separator: ", "))). "
                    + "Nothing was changed — mark the intended job by number."
            case let .invalidURL(url):
                "Not a usable job posting URL: \(url)"
            }
        }
    }

    /// Statuses at or past Applied that must never be silently regressed by an automated caller.
    private static let atOrPastApplied: Set<JobStatus> = [.applied, .interview, .offer]

    /// Mark the job at `url` as Applied, creating a minimal record when the posting was never captured.
    ///
    /// Resolution is conservative: exact capture URL / stored canonical URL first, then a normalized
    /// comparison (so tracking-param and trailing-slash variants resolve), then the job's own
    /// `applicationURL`. Multiple distinct matches abort without mutating anything. Repeating the call
    /// is a no-op — status transitions run through the normal path, so `appliedAt` and the auditable
    /// status event stay correct and aren't re-stamped.
    public func markJobApplied(
        url: String, company: String? = nil, title: String? = nil, pageTitle _: String? = nil,
        applicationURL: String? = nil, note: String? = nil
    ) async throws -> MarkAppliedResult {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validated = try? URLNormalizer.validatedForIngestion(trimmed) else {
            throw MarkAppliedError.invalidURL(trimmed)
        }

        if let job = try await resolveJob(forURL: validated) {
            return try await applyToExisting(job, matchedURL: validated, note: note)
        }

        // No match — create one minimal record via the existing URL-only ingestion path (the same one
        // the app's "Add Job by URL" uses), so job numbering, URL policy and dedupe all come from one
        // place. It queues extraction against the URL as synthetic content; we deliberately don't wait
        // for that before recording the application.
        let result = try await addJobByURL(validated)
        // Fill in what the caller told us and transition — one store hop each, but the job is created
        // Applied-or-nothing from the caller's perspective because a failure here surfaces as an error.
        // `#Predicate` can't reference a struct member — bind it locally first.
        let createdNumber: Int? = result.jobNumber
        guard let job = try await store.fetch(FetchDescriptor<Job>(
            predicate: #Predicate { $0.jobNumber == createdNumber }
        )).first else { throw JobServiceError.jobNotFound(validated) }
        let jobID = job.id
        let cleanCompany = company?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanApplication = applicationURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if cleanCompany != nil || cleanTitle != nil || cleanApplication != nil {
            try await store.update(Job.self, predicate: #Predicate { $0.id == jobID }) { job in
                if let cleanCompany, job.company?.isEmpty ?? true { job.company = cleanCompany }
                if let cleanTitle, job.title?.isEmpty ?? true { job.title = cleanTitle }
                if let cleanApplication, job.applicationURL == nil { job.applicationURL = cleanApplication }
                job.updatedAt = Date()
            }
        }
        try await setStatus(.applied, for: jobID)
        let saved = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })).first
        return MarkAppliedResult(
            jobID: jobID, jobNumber: saved?.jobNumber ?? result.jobNumber,
            company: saved?.company, title: saved?.title,
            previousStatus: JobStatus.new.rawValue, status: JobStatus.applied.rawValue,
            created: true, alreadyApplied: false, laterStage: false,
            matchedURL: validated, appliedAt: saved?.appliedAt
        )
    }

    /// Resolve a job from a posting URL, refusing to guess when several distinct jobs match.
    private func resolveJob(forURL url: String) async throws -> Job? {
        let exact = try await store.fetch(FetchDescriptor<Capture>(
            predicate: #Predicate { $0.url == url || $0.canonicalURL == url }
        ))
        if let job = exact.first?.job { return job }

        guard let target = URLNormalizer.normalized(url) else { return nil }
        let captures = try await store.fetch(FetchDescriptor<Capture>())
        var matched: [Job] = []
        for capture in captures {
            let canonicalMatches = capture.canonicalURL.map { URLNormalizer.normalized($0) == target } ?? false
            guard canonicalMatches || URLNormalizer.normalized(capture.url) == target else { continue }
            if let job = capture.job, !matched.contains(where: { $0.id == job.id }) { matched.append(job) }
        }
        if matched.isEmpty {
            // Last resort: the job's own application URL (where you actually submitted).
            let jobs = try await store.fetch(FetchDescriptor<Job>())
            matched = jobs.filter { $0.applicationURL.map { URLNormalizer.normalized($0) == target } ?? false }
        }
        if matched.isEmpty {
            matched = try await jobsMatchingATSID(of: url)
        }
        if matched.count > 1 {
            throw MarkAppliedError.ambiguous(matches: matched.compactMap(\.jobNumber).sorted())
        }
        return matched.first
    }

    /// Jobs carrying the same ATS posting id as `url` (TASK-648 #1).
    ///
    /// The same Greenhouse posting reached via `boards.greenhouse.io/acme/jobs/12345` and via an
    /// embedded `acme.com/careers?gh_jid=12345` has two URL shapes that no amount of normalization
    /// reconciles — one is a path, the other a query parameter on a different host. The id is the
    /// thing that's actually equal, so it's *extracted and compared*, never normalized away.
    ///
    /// Deliberately last: URL matching is exact and this is an inference. `gh_jid` is only
    /// company-unique in principle, and two postings on one embedded board must stay distinct —
    /// which they do, because their ids differ (pinned by a test).
    private func jobsMatchingATSID(of url: String) async throws -> [Job] {
        guard let atsID = DuplicateDetector.atsPostingID(urlString: url) else { return [] }
        var matched: [Job] = []
        for capture in try await store.fetch(FetchDescriptor<Capture>()) {
            let ids = [capture.url, capture.canonicalURL, capture.job?.applicationURL]
                .compactMap(\.self)
                .compactMap { DuplicateDetector.atsPostingID(urlString: $0) }
            guard ids.contains(atsID), let job = capture.job,
                  !matched.contains(where: { $0.id == job.id }) else { continue }
            matched.append(job)
        }
        return matched
    }

    private func applyToExisting(_ job: Job, matchedURL: String, note: String?) async throws -> MarkAppliedResult {
        let jobID = job.id
        let previous = job.status
        func result(created: Bool, alreadyApplied: Bool, laterStage: Bool, status: JobStatus) async throws
            -> MarkAppliedResult {
            let saved = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })).first
            return MarkAppliedResult(
                jobID: jobID, jobNumber: saved?.jobNumber, company: saved?.company, title: saved?.title,
                previousStatus: previous.rawValue, status: status.rawValue,
                created: created, alreadyApplied: alreadyApplied, laterStage: laterStage,
                matchedURL: matchedURL, appliedAt: saved?.appliedAt
            )
        }
        // Already at or past Applied: never regress, never re-stamp, never re-log.
        if Self.atOrPastApplied.contains(previous) {
            return try await result(
                created: false, alreadyApplied: previous == .applied,
                laterStage: previous != .applied, status: previous
            )
        }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await addNote(note, to: jobID)
        }
        try await setStatus(.applied, for: jobID)
        return try await result(created: false, alreadyApplied: false, laterStage: false, status: .applied)
    }
}
