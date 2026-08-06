import CryptoKit
import Foundation
import SwiftData

// MARK: - Public types

/// Capture ingestion payload (matches extension POST /captures body).
extension String {
    /// `nil` when the string is empty, so optional metadata doesn't overwrite real values with "".
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public struct CapturePayload: Sendable {
    public let url: String
    public let pageTitle: String
    public let selectedText: String?
    public let visibleText: String?
    public let userNote: String?
    public let canonicalURL: String?
    public let structuredDataJSON: String?

    public init(
        url: String,
        pageTitle: String,
        selectedText: String? = nil,
        visibleText: String? = nil,
        userNote: String? = nil,
        canonicalURL: String? = nil,
        structuredDataJSON: String? = nil
    ) {
        self.url = url
        self.pageTitle = pageTitle
        self.selectedText = selectedText
        self.visibleText = visibleText
        self.userNote = userNote
        self.canonicalURL = canonicalURL
        self.structuredDataJSON = structuredDataJSON
    }
}

/// Response matching extension contract exactly.
public struct IngestResult: Sendable {
    public let captureID: String
    public let jobNumber: Int
    public let isDuplicate: Bool

    public init(captureID: String, jobNumber: Int, isDuplicate: Bool) {
        self.captureID = captureID
        self.jobNumber = jobNumber
        self.isDuplicate = isDuplicate
    }
}

public enum JobServiceError: Error, LocalizedError, Sendable {
    case missingURL
    case invalidURL
    case missingPageTitle
    case missingText
    case jobNotFound(String)
    case actionNotFound(String)
    case contactNotFound(String)
    case coverLetterNotFound(String)
    case invalidStatus(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL: "Job URL is required"
        case .invalidURL: "Job URL must be a valid http or https web address"
        case .missingPageTitle: "Job page title is required"
        case .missingText: "Job description text is required"
        case .jobNotFound: "Job not found"
        case .actionNotFound: "Action item not found"
        case .contactNotFound: "Contact not found"
        case .coverLetterNotFound: "Cover letter not found"
        case let .invalidStatus(raw):
            "Invalid status '\(raw)'; valid values: " + JobStatus.allCases.map(\.rawValue).joined(separator: ", ")
        }
    }
}

// MARK: - JobService

public actor JobService {
    let store: BackgroundStore
    private let queue: QueueActor

    public init(store: BackgroundStore, queue: QueueActor) {
        self.store = store
        self.queue = queue
    }

    // MARK: - Core ingestion

    /// Validate → clean → hash → dedup → create Job → enqueue extraction.
    public func ingestCapture(_ payload: CapturePayload) async throws -> IngestResult {
        // 1. Validate — one shared URL policy (TASK-443). Reject before any persistence/enqueue.
        guard !payload.url.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw JobServiceError.missingURL
        }
        let validatedURL: String
        do {
            validatedURL = try URLNormalizer.validatedForIngestion(payload.url)
        } catch {
            throw JobServiceError.invalidURL
        }
        // A canonical URL is optional metadata; normalize it if valid, otherwise drop it (don't fail
        // the whole capture over a malformed <link rel="canonical"> the site emitted).
        // A canonical that doesn't identify this posting is dropped, not stored: ingestion treats a
        // canonical match as proof of sameness and overwrites the existing capture, so a search-page
        // canonical shared by every job on an SPA board silently destroys data (see
        // CanonicalURLPolicy).
        let validatedCanonical: String? = payload.canonicalURL
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            .flatMap { try? URLNormalizer.validatedForIngestion($0) }
            .flatMap { CanonicalURLPolicy.trustworthyCanonical($0, captureURL: validatedURL) }
        guard !payload.pageTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw JobServiceError.missingPageTitle
        }
        let selectedTrimmed = payload.selectedText?.trimmingCharacters(in: .whitespaces) ?? ""
        let visibleTrimmed = payload.visibleText?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !selectedTrimmed.isEmpty || !visibleTrimmed.isEmpty else {
            throw JobServiceError.missingText
        }

        // 2. Clean
        let structuredData: [[String: Any]] = if let jsonStr = payload.structuredDataJSON,
                                                 let data = jsonStr.data(using: .utf8),
                                                 let parsed = try? JSONSerialization
                                                 .jsonObject(with: data) as? [[String: Any]] {
            parsed
        } else {
            []
        }
        let cleanedDescription = cleanDescription(
            selectedText: payload.selectedText ?? "",
            visibleText: payload.visibleText ?? "",
            structuredData: structuredData
        )

        // 3. Hash
        let rawHashValue = DuplicateDetector.rawHash(
            url: validatedURL,
            canonicalURL: validatedCanonical,
            selectedText: payload.selectedText,
            visibleText: payload.visibleText,
            structuredData: structuredData
        )
        let cleanedHashValue = cleanedDescription.isEmpty
            ? nil
            : DuplicateDetector.cleanedHash(from: cleanedDescription)

        // 4-7. Atomic dedup check, job number assignment, and insert of Capture + Job + LLMRequest
        let captureID = "cap-\(UUID().uuidString)"
        let jobID = "job-\(UUID().uuidString)"

        let input = AtomicIngestInput(
            captureID: captureID,
            jobID: jobID,
            url: validatedURL,
            canonicalURL: validatedCanonical,
            pageTitle: payload.pageTitle,
            selectedText: payload.selectedText,
            visibleText: payload.visibleText,
            cleanedDescription: cleanedDescription.isEmpty ? nil : cleanedDescription,
            structuredDataJSON: payload.structuredDataJSON,
            userNote: payload.userNote,
            rawHash: rawHashValue,
            cleanedHash: cleanedHashValue
        )
        let atomic = try await store.insertCaptureAtomically(input)

        // TASK-491: a new job (or a re-capture) queues an extraction request directly inside the
        // atomic insert — it does NOT go through queue.enqueue, so nothing kicks the drain loop.
        // Without this, captures sit "Queued" whenever the loop has already drained and exited, and
        // the user has to hit Resume to get them processed. Kick it here (no-op if paused / already
        // running). Exact duplicates queue nothing, so skip them.
        if !atomic.isDuplicate {
            await queue.kick()
        }

        // 8. Return result
        return IngestResult(
            captureID: atomic.captureID,
            jobNumber: atomic.jobNumber,
            isDuplicate: atomic.isDuplicate
        )
    }

    // swiftlint:enable function_body_length

    // MARK: - URL-only ingestion

    /// Add a job by URL alone (no browser-captured content). Uses the URL as synthetic content
    /// so extraction has something to work with (URL paths often contain company and job keywords).
    public func addJobByURL(_ urlString: String) async throws -> IngestResult {
        guard !urlString.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw JobServiceError.missingURL
        }
        // Same shared URL policy as capture ingestion (TASK-443) — reject non-http(s)/malformed
        // before any persistence or enqueue.
        let validated: String
        do {
            validated = try URLNormalizer.validatedForIngestion(urlString)
        } catch {
            throw JobServiceError.invalidURL
        }

        let rawHash = DuplicateDetector.rawHash(
            url: validated,
            canonicalURL: nil,
            selectedText: nil,
            visibleText: validated,
            structuredData: []
        )
        let input = AtomicIngestInput(
            captureID: "cap-\(UUID().uuidString)",
            jobID: "job-\(UUID().uuidString)",
            url: validated,
            canonicalURL: nil,
            pageTitle: validated,
            selectedText: nil,
            visibleText: validated,
            cleanedDescription: validated,
            structuredDataJSON: nil,
            userNote: nil,
            rawHash: rawHash,
            cleanedHash: nil
        )
        let atomic = try await store.insertCaptureAtomically(input)
        if !atomic.isDuplicate {
            // insertCaptureAtomically already inserted the .queued extraction request for this job.
            // This enqueue does NOT create a second one — QueueActor.enqueue dedups against existing
            // queued/running requests for the same (job, mode) — its job here is to KICK THE DRAIN
            // (insertCaptureAtomically doesn't). Don't drop this call thinking it's redundant, or
            // manual-URL jobs would never start processing. (TASK-448 regression tests assert exactly
            // one extraction request results.)
            try await queue.enqueue(jobIDs: [input.jobID], mode: .extract)
        }
        return IngestResult(captureID: atomic.captureID, jobNumber: atomic.jobNumber, isDuplicate: atomic.isDuplicate)
    }

    // MARK: - Job mutations

    public func setStatus(_ status: JobStatus, for jobID: String) async throws {
        do {
            try await store.setJobStatus(status, jobIDs: [jobID])
        } catch BackgroundStoreError.notFound(_) {
            throw JobServiceError.jobNotFound(jobID)
        }
    }

    public func setStatusBulk(_ status: JobStatus, jobIDs: [String]) async throws {
        do {
            try await store.setJobStatus(status, jobIDs: jobIDs)
        } catch let BackgroundStoreError.notFound(id) {
            throw JobServiceError.jobNotFound(id)
        }
    }

    public func addNote(_ text: String, to jobID: String) async throws {
        // TASK-526/578: created + linked inside the store actor. requireJob:true so adding a note to a
        // job that was deleted (e.g. mid-sheet) surfaces an error instead of silently saving nothing.
        do {
            try await store.insertJobEvent(jobID: jobID, eventType: "note", note: text, requireJob: true)
        } catch BackgroundStoreError.notFound {
            throw JobServiceError.jobNotFound(jobID)
        }
    }

    /// Edit a note event in place. Saving empty/whitespace-only text deletes the note
    /// (the UI's "delete = edit and save empty" convention, review-2 #2).
    public func updateNote(eventID: String, text: String) async throws {
        let id = eventID
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try await store.deleteOne(JobEvent.self, predicate: #Predicate { $0.id == id }, id: id)
        } else {
            try await store.update(JobEvent.self, predicate: #Predicate { $0.id == id }) { event in
                event.note = trimmed
            }
        }
    }

    /// Re-insert a deleted note, preserving its original timeline position. Used by the "Undo"
    /// toast after a note delete (the deleted event is gone, so this creates an equivalent one
    /// with the same text and timestamps rather than resurrecting the original row).
    public func restoreNote(jobID: String, text: String, occurredAt: Date, createdAt: Date) async throws {
        do {
            try await store.insertJobEvent(
                jobID: jobID,
                eventType: "note",
                note: text,
                occurredAt: occurredAt,
                createdAt: createdAt,
                requireJob: true
            )
        } catch BackgroundStoreError.notFound {
            throw JobServiceError.jobNotFound(jobID)
        }
    }

    public func archive(jobID: String) async throws {
        try await setStatus(.archived, for: jobID)
    }

    public func delete(jobID: String) async throws {
        let id = jobID
        try await store.deleteOne(Job.self, predicate: #Predicate { $0.id == id }, id: jobID)
        // `ReferralAttempt` is keyed by `jobID` with no SwiftData relationship, so it isn't cascaded —
        // without this the job's attempts and its N/A marker outlive it forever (TASK-644 review).
        try await store.deleteReferralAttempts(jobID: jobID)
        try await store.deleteMilestones(jobID: jobID)
    }

    public func markOpened(jobID: String) async throws {
        let id = jobID
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            job.lastOpenedAt = Date()
            job.unread = false
            job.updatedAt = Date()
        }
    }

    public func markRead(jobID: String) async throws {
        let id = jobID
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            job.unread = false
            job.updatedAt = Date()
        }
    }

    public func setRating(_ rating: Int?, for jobID: String) async throws {
        let id = jobID
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            job.rating = rating
            job.updatedAt = Date()
        }
    }

    public func updateSkills(_ skills: [String], for jobID: String) async throws {
        let id = jobID
        let encoded = (try? String(data: JSONEncoder().encode(skills), encoding: .utf8)) ?? "[]"
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            job.manualOverridesJSON = encoded
            job.updatedAt = Date()
        }
    }

    // MARK: - Actions

    public func createAction(jobID: String, text: String, dueAt: Date?) async throws {
        // TASK-526/578: created + linked inside the store actor; a missing job is a user-visible
        // error, not a silent no-op.
        do {
            try await store.insertJobAction(jobID: jobID, note: text, dueDate: dueAt ?? Date())
        } catch BackgroundStoreError.notFound {
            throw JobServiceError.jobNotFound(jobID)
        }
    }

    public func completeAction(actionID: String) async throws {
        let id = actionID
        try await store.update(JobAction.self, predicate: #Predicate { $0.id == id }) { action in
            action.completedAt = Date()
            action.updatedAt = Date()
        }
    }

    /// Reverse `completeAction` — used by the "Undo" toast after marking a follow-up done.
    public func reopenAction(actionID: String) async throws {
        let id = actionID
        try await store.update(JobAction.self, predicate: #Predicate { $0.id == id }) { action in
            action.completedAt = nil
            action.updatedAt = Date()
        }
    }

    /// Edit a follow-up's text in place. Saving empty/whitespace-only text deletes the
    /// follow-up (the UI's "delete = edit and save empty" convention, review-2 #2).
    public func updateAction(actionID: String, text: String) async throws {
        let id = actionID
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try await store.deleteOne(JobAction.self, predicate: #Predicate { $0.id == id }, id: id)
        } else {
            try await store.update(JobAction.self, predicate: #Predicate { $0.id == id }) { action in
                action.note = trimmed
                action.updatedAt = Date()
            }
        }
    }

    public func deleteAction(actionID: String) async throws {
        let id = actionID
        try await store.deleteOne(JobAction.self, predicate: #Predicate { $0.id == id }, id: id)
    }

    public func snoozeAction(actionID: String, until: Date) async throws {
        let id = actionID
        try await store.update(JobAction.self, predicate: #Predicate { $0.id == id }) { action in
            action.snoozedUntil = until
            action.updatedAt = Date()
        }
    }

    // MARK: - Contacts

    public func createContact(jobID: String, name: String, email: String?, role: String?) async throws {
        // TASK-526: created + linked inside the store actor.
        try await store.insertContact(jobID: jobID, name: name, role: role, email: email)
    }

    public func updateContact(contactID: String, name: String, email: String?, role: String?) async throws {
        let id = contactID
        try await store.update(Contact.self, predicate: #Predicate { $0.id == id }) { contact in
            contact.name = name
            contact.email = email
            contact.role = role
            contact.updatedAt = Date()
        }
    }

    public func deleteContact(contactID: String) async throws {
        let id = contactID
        try await store.delete(Contact.self, predicate: #Predicate { $0.id == id })
    }

    // MARK: - Cover letters

    public func deleteCoverLetter(id: String) async throws {
        let covID = id
        try await store.delete(CoverLetter.self, predicate: #Predicate { $0.id == covID })
    }

    // MARK: - Data quality

    public func markDataQualityReviewed(jobID: String, notes: String?) async throws {
        // TASK-526: upsert inside the store actor.
        try await store.upsertDataQualityReview(jobID: jobID, note: notes ?? "")
    }

    public func clearDataQualityReview(jobID: String) async throws {
        try await store.clearDataQualityReview(jobID: jobID)
    }

    // MARK: - Bulk LLM ops

    public func enqueueLLM(jobIDs: [String], mode: LLMRequestType) async throws {
        try await queue.enqueue(jobIDs: jobIDs, mode: mode)
    }

    public func resetExtraction(jobID: String) async throws {
        let id = jobID
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            job.extractionStatus = .pending
            job.extractionError = nil
            // TASK-517: centralized, override-aware clearing (was missing salaryHourly*, applicationURL,
            // meetsCriteria — and cleared overridden fields unconditionally, losing manual edits).
            clearExtractionOwnedFields(job)
            job.updatedAt = Date()
        }
        try await queue.enqueue(jobIDs: [jobID], mode: .extract)
    }

    /// Re-run fit scoring for these jobs against every active résumé.
    ///
    /// Distinct from `recomputeAllFitScores`, which re-derives the arithmetic from stored judgments
    /// for free: this discards the model's judgments and asks again, which is what a scoring-prompt
    /// change requires. Returns the number of scoring requests enqueued.
    @discardableResult
    public func rescoreFit(jobIDs: [String]) async throws -> Int {
        try await queue.enqueueFitForActiveResumes(jobIDs: jobIDs)
        await queue.kick()
        return jobIDs.count
    }

    public func resetExtractionBulk(jobIDs: [String]) async throws {
        for jobID in jobIDs {
            try await resetExtraction(jobID: jobID)
        }
    }

    /// Recompute all stored fit scores from saved JSON with the current weights/penalties — no
    /// LLM calls (Electron parity: rescore.js). Returns the number of scores updated.
    public func recomputeAllFitScores() async throws -> Int {
        try await store.recomputeAllFitScores()
    }

    /// How many stored requirement assessments each correction currently matches, keyed by its id —
    /// so a rule that has been orphaned by a re-score, or one matching far more than intended, is
    /// visible in Settings rather than only in the scores.
    /// Measured reach of a correction the user hasn't saved yet — see `FeedbackMatchPreview`.
    public func scoringFeedbackMatchPreview(
        phrase: String,
        kind: ScoringFeedback.Kind,
        jobNumber: Int?
    ) async throws -> FeedbackMatchPreview {
        try await store.scoringFeedbackMatchPreview(phrase: phrase, kind: kind, jobNumber: jobNumber)
    }

    public func scoringFeedbackMatchCounts(_ feedback: [ScoringFeedback]) async throws -> [String: Int] {
        try await store.scoringFeedbackMatchCounts(feedback)
    }

    // MARK: - Field-level updates (used by detail inspector)

    /// Update individual string/enum fields on a job. Pass nil to leave a field unchanged.
    public func updateJobFields(
        jobID: String,
        company: String?? = .none,
        title: String?? = .none,
        location: String?? = .none,
        remoteType: RemoteType?? = .none,
        applicationURL: String?? = .none,
        duplicateOfJobID: String?? = .none,
        salaryMin: Int?? = .none,
        salaryMax: Int?? = .none,
        salaryCurrency: String?? = .none,
        salaryNote: String?? = .none
    ) async throws {
        let id = jobID
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            // Record which extraction-owned fields the user edited so re-extraction won't clobber them.
            var overrides = manualFieldOverrideSet(job.manualFieldOverridesJSON)
            if let v = company { job.company = v; overrides.insert("company") }
            if let v = title { job.title = v; overrides.insert("title") }
            if let v = location { job.location = v; overrides.insert("location") }
            if let v = remoteType { job.remoteType = v; overrides.insert("remoteType") }
            if let v = applicationURL { job.applicationURL = v; overrides.insert("applicationURL") }
            if let v = duplicateOfJobID {
                job.duplicateOfJobID = v // not an extraction field
                // Invariant repair (TASK-370): keep status consistent with the duplicate link.
                if v != nil {
                    job.status = .duplicate
                } else if job.status == .duplicate {
                    job.status = .new
                }
                job.duplicateConfidence = v == nil ? nil : job.duplicateConfidence
            }
            if let v = salaryMin { job.salaryMin = v; overrides.insert("salaryMin") }
            if let v = salaryMax { job.salaryMax = v; overrides.insert("salaryMax") }
            if let v = salaryCurrency { job.salaryCurrency = v; overrides.insert("salaryCurrency") }
            if let v = salaryNote { job.salaryNote = v; overrides.insert("salaryNote") }
            job.manualFieldOverridesJSON = manualFieldOverrideJSON(overrides)
            job.updatedAt = Date()
        }
    }

    /// Clear all manual field overrides for a job so the next extraction repopulates every field.
    public func clearFieldOverrides(jobID: String) async throws {
        let id = jobID
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            job.manualFieldOverridesJSON = nil
            job.updatedAt = Date()
        }
    }

    // MARK: - URL lookup (used by server /api/jobs/by-url)

    /// Find the job_number for the first job whose capture URL matches the given URL.
    /// Returns nil if no match found.
    public func findJobNumber(byURL url: String) async throws -> Int? {
        // TASK-444: bounded exact match first — original url OR stored canonical url.
        let exact = try await store.fetch(FetchDescriptor<Capture>(
            predicate: #Predicate { $0.url == url || $0.canonicalURL == url }
        ))
        if let job = exact.first?.job { return job.jobNumber }

        // Fallback (only when the indexed lookup misses): compare normalized forms, so a tab reached
        // via a canonical/tracking-param/trailing-slash variant still resolves to the captured job.
        guard let target = URLNormalizer.normalized(url) else { return nil }
        let all = try await store.fetch(FetchDescriptor<Capture>())
        let match = all.first { cap in
            if let canon = cap.canonicalURL, URLNormalizer.normalized(canon) == target { return true }
            return URLNormalizer.normalized(cap.url) == target
        }
        return match?.job?.jobNumber
    }

    // MARK: - MCP read queries

    /// Filtered, offset-paged job list with an exact `total`.
    ///
    /// Every filter is applied in memory after one sorted fetch. SwiftData can't predicate on the
    /// enum `status` or reach through to the capture's cleaned text, and an exact `total` requires
    /// counting all matches anyway — so the chunked scan this replaces couldn't produce one. At this
    /// app's scale (hundreds of jobs, per the project conventions) a single pass is imperceptible and
    /// far easier to reason about than paging with predicates that can't express the filters.
    public func listJobs(_ query: JobQuery) async throws -> JobListPage {
        let offset = max(0, query.offset)
        let limit = max(0, query.limit)

        if let statusRaw = query.status, JobStatus(rawValue: statusRaw) == nil {
            throw JobServiceError.invalidStatus(statusRaw)
        }
        let wantedStatus = query.status.flatMap { JobStatus(rawValue: $0) }
        let needle = query.query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let companyNeedle = query.company?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let descriptor = FetchDescriptor<Job>(
            sortBy: [
                SortDescriptor(\Job.createdAt, order: .reverse),
                SortDescriptor(\Job.id, order: .reverse)
            ]
        )
        let all = try await store.fetch(descriptor)

        let matches = all.filter { job in
            if let wantedStatus, job.status != wantedStatus { return false }
            if let companyNeedle, !companyNeedle.isEmpty {
                guard (job.company ?? "").lowercased().contains(companyNeedle) else { return false }
            }
            if let after = query.capturedAfter {
                let captured = job.capture?.capturedAt ?? job.capture?.createdAt ?? job.createdAt
                guard captured >= after else { return false }
            }
            if let scoreFloor = query.minScore {
                // An unscored job can't be shown to clear a threshold, so it's excluded rather than
                // assumed to pass.
                guard let score = job.fitScore, score >= scoreFloor else { return false }
            }
            if let floor = query.minSalary {
                // No stated salary can't clear a floor — excluded only because a floor was asked for.
                guard let ceiling = job.salaryMax ?? job.salaryMin, ceiling >= floor else { return false }
            }
            if let needle, !needle.isEmpty {
                guard Self.matchesText(job, needle: needle) else { return false }
            }
            return true
        }

        let page = matches.dropFirst(offset).prefix(limit)
        return JobListPage(
            records: page.map { JobListRecord(job: $0) },
            total: matches.count,
            offset: offset,
            limit: limit
        )
    }

    /// Substring match across the fields a keyword question would plausibly target, including the
    /// cleaned description — the whole point is not having to pull every record to grep it.
    private static func matchesText(_ job: Job, needle: String) -> Bool {
        let haystacks = [
            job.title, job.company, job.location, job.seniority, job.employmentType,
            job.capture?.pageTitle, job.capture?.cleanedDescription
        ]
        return haystacks.contains { ($0 ?? "").lowercased().contains(needle) }
    }

    public func getJob(byNumber number: Int) async throws -> JobDetailRecord? {
        let descriptor = FetchDescriptor<Job>(
            predicate: #Predicate { $0.jobNumber == number }
        )
        let jobs = try await store.fetch(descriptor)
        return jobs.first.map { JobDetailRecord(job: $0) }
    }

    /// Fetch a job by its internal id string (MCP `job_id` back-compat — TASK-464).
    public func getJob(byID id: String) async throws -> JobDetailRecord? {
        let descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == id })
        let jobs = try await store.fetch(descriptor)
        return jobs.first.map { JobDetailRecord(job: $0) }
    }

    public func workflowSnapshot() async throws -> WorkflowSnapshot {
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let sites = try await store.fetch(FetchDescriptor<Site>())
        var counts: [String: Int] = [:]
        var extractionCounts: [String: Int] = [:]
        for job in jobs {
            counts[job.status.rawValue, default: 0] += 1
            extractionCounts[job.extractionStatus.rawValue, default: 0] += 1
        }
        let now = Date()
        let sitesDue = sites.count(where: { $0.state != .exclude && ($0.nextReviewAt.map { $0 <= now } ?? true) })
        return WorkflowSnapshot(
            jobsTotal: jobs.count,
            sitesTotal: sites.count,
            statusCounts: counts,
            sitesDue: sitesDue,
            extractionStatusCounts: extractionCounts
        )
    }

    // MARK: - Duplicate management

    /// Mark `jobID` as a duplicate of `ofJobID`, maintaining the invariant
    /// (`duplicateOfJobID != nil` ⇒ `status == .duplicate`) atomically. Prefer this over setting
    /// `duplicateOfJobID` through the generic field-update path (TASK-370).
    public func markDuplicate(jobID: String, ofJobID: String, confidence: Double? = nil) async throws {
        let id = jobID
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            job.duplicateOfJobID = ofJobID
            job.duplicateConfidence = confidence
            job.status = .duplicate
            job.updatedAt = Date()
        }
    }

    /// Clear the duplicate relationship for a job, keeping it in the job list.
    /// Clears `duplicateOfJobID` and, if `status` was `.duplicate`, resets it to `.new`
    /// so the job reappears in normal status folders. A non-duplicate status (e.g. `.pursuing`)
    /// is preserved as-is.
    public func unmarkDuplicate(jobID: String) async throws {
        try await store.update(Job.self, predicate: #Predicate { $0.id == jobID }) { job in
            job.duplicateOfJobID = nil
            // TASK-518: the confidence is meaningless without the link — clear it too, matching
            // setStatus's invariant repair and updateJobFields.
            job.duplicateConfidence = nil
            if job.status == .duplicate {
                job.status = .new
            }
            job.updatedAt = Date()
        }
    }

    /// Record a duplicate decision (e.g. "not_duplicate") so a dismissed pair does not resurface
    /// in automatic domain-duplicate detection.
    public func decideDuplicate(cleanedHash: String, decision: String, keepJobID: String?) async throws {
        try await store.upsertDuplicateDecision(cleanedHash: cleanedHash, decision: decision, keepJobID: keepJobID)
    }

    // MARK: - Availability

    /// Bulk-mark a set of jobs as expired (e.g. after availability check confirms they're gone).
    ///
    /// Routes through `setJobStatus` (TASK-515) so each job gets the same auditable "status" timeline
    /// event as any other status change — expiration is a terminal decision and the timeline should
    /// explain it — and so the duplicate-link invariants stay consistent. Throws `jobNotFound` if any
    /// id is missing rather than silently skipping it, so a confirmed change can't be reported as
    /// succeeding when it didn't.
    public func markExpired(jobIDs: [String]) async throws {
        guard !jobIDs.isEmpty else { return }
        do {
            try await store.setJobStatus(.expired, jobIDs: jobIDs)
        } catch let BackgroundStoreError.notFound(id) {
            throw JobServiceError.jobNotFound(id)
        }
    }

    // MARK: - Saved searches

    /// Persist a new saved search.
    public func insertSavedSearch(_ search: SavedSearch) async throws {
        try await store.insert(search)
    }

    /// Delete a saved search by ID.
    public func deleteSavedSearch(id: String) async throws {
        try await store.delete(SavedSearch.self, predicate: #Predicate { $0.id == id })
    }
}
