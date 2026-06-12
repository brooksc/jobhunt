import CryptoKit
import Foundation
import SwiftData

// MARK: - Public types

/// Capture ingestion payload (matches extension POST /captures body).
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
    case missingPageTitle
    case missingText
    case jobNotFound(String)
    case actionNotFound(String)
    case contactNotFound(String)
    case coverLetterNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL: "Job URL is required"
        case .missingPageTitle: "Job page title is required"
        case .missingText: "Job description text is required"
        case .jobNotFound: "Job not found"
        case .actionNotFound: "Action item not found"
        case .contactNotFound: "Contact not found"
        case .coverLetterNotFound: "Cover letter not found"
        }
    }
}

// MARK: - JobService

public actor JobService {
    private let store: BackgroundStore
    private let queue: QueueActor

    public init(store: BackgroundStore, queue: QueueActor) {
        self.store = store
        self.queue = queue
    }

    // MARK: - Core ingestion

    // swiftlint:disable function_body_length
    /// Validate → clean → hash → dedup → create Job → enqueue extraction.
    public func ingestCapture(_ payload: CapturePayload) async throws -> IngestResult {
        // 1. Validate
        guard !payload.url.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw JobServiceError.missingURL
        }
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
            url: payload.url,
            canonicalURL: payload.canonicalURL,
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
            url: payload.url,
            canonicalURL: payload.canonicalURL,
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
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else {
            throw JobServiceError.missingURL
        }

        let rawHash = DuplicateDetector.rawHash(
            url: trimmed,
            canonicalURL: nil,
            selectedText: nil,
            visibleText: trimmed,
            structuredData: []
        )
        let input = AtomicIngestInput(
            captureID: "cap-\(UUID().uuidString)",
            jobID: "job-\(UUID().uuidString)",
            url: trimmed,
            canonicalURL: nil,
            pageTitle: trimmed,
            selectedText: nil,
            visibleText: trimmed,
            cleanedDescription: trimmed,
            structuredDataJSON: nil,
            userNote: nil,
            rawHash: rawHash,
            cleanedHash: nil
        )
        let atomic = try await store.insertCaptureAtomically(input)
        if !atomic.isDuplicate {
            try await queue.enqueue(jobIDs: [input.jobID], mode: .extract)
        }
        return IngestResult(captureID: atomic.captureID, jobNumber: atomic.jobNumber, isDuplicate: atomic.isDuplicate)
    }

    // MARK: - Job mutations

    public func setStatus(_ status: JobStatus, for jobID: String) async throws {
        let id = jobID
        try await store.updateOne(Job.self, predicate: #Predicate { $0.id == id }, id: jobID) { job in
            job.status = status
            job.updatedAt = Date()
        }
    }

    public func setStatusBulk(_ status: JobStatus, jobIDs: [String]) async throws {
        guard !jobIDs.isEmpty else { return }
        let ids = jobIDs
        let newStatus = status
        try await store.update(Job.self, predicate: #Predicate { ids.contains($0.id) }) { job in
            job.status = newStatus
            job.updatedAt = Date()
        }
    }

    public func addNote(_ text: String, to jobID: String) async throws {
        let id = jobID
        let event = JobEvent(eventType: "note", note: text)
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == id }))
        guard let job = jobs.first else { throw JobServiceError.jobNotFound(jobID) }
        event.job = job
        try await store.insert(event)
    }

    public func archive(jobID: String) async throws {
        try await setStatus(.archived, for: jobID)
    }

    public func delete(jobID: String) async throws {
        let id = jobID
        try await store.deleteOne(Job.self, predicate: #Predicate { $0.id == id }, id: jobID)
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
        let id = jobID
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == id }))
        guard let job = jobs.first else { throw JobServiceError.jobNotFound(jobID) }
        let action = JobAction(note: text, dueDate: dueAt ?? Date())
        action.job = job
        try await store.insert(action)
    }

    public func completeAction(actionID: String) async throws {
        let id = actionID
        try await store.update(JobAction.self, predicate: #Predicate { $0.id == id }) { action in
            action.completedAt = Date()
            action.updatedAt = Date()
        }
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
        let id = jobID
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == id }))
        guard let job = jobs.first else { throw JobServiceError.jobNotFound(jobID) }
        let contact = Contact(name: name, role: role, email: email)
        contact.job = job
        try await store.insert(contact)
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
        let id = jobID
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == id }))
        guard let job = jobs.first else { throw JobServiceError.jobNotFound(jobID) }

        if let existing = job.qualityReview {
            existing.reviewedAt = Date()
            existing.note = notes ?? ""
            try await store.save()
        } else {
            let review = DataQualityReview(reviewedAt: Date(), note: notes ?? "")
            review.job = job
            try await store.insert(review)
        }
    }

    public func clearDataQualityReview(jobID: String) async throws {
        let id = jobID
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == id }))
        guard let job = jobs.first else { throw JobServiceError.jobNotFound(jobID) }
        if let review = job.qualityReview {
            try await store.deleteObject(review)
        }
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
            job.extractedAt = nil
            job.company = nil
            job.title = nil
            job.location = nil
            job.remoteType = nil
            job.salaryMin = nil
            job.salaryMax = nil
            job.salaryCurrency = nil
            job.salaryNote = nil
            job.employmentType = nil
            job.seniority = nil
            job.extractedJSON = nil
            job.extractionModel = nil
            job.extractionConfidence = nil
            job.updatedAt = Date()
        }
        try await queue.enqueue(jobIDs: [jobID], mode: .extract)
    }

    public func resetExtractionBulk(jobIDs: [String]) async throws {
        for jobID in jobIDs {
            try await resetExtraction(jobID: jobID)
        }
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
            if let v = company { job.company = v }
            if let v = title { job.title = v }
            if let v = location { job.location = v }
            if let v = remoteType { job.remoteType = v }
            if let v = applicationURL { job.applicationURL = v }
            if let v = duplicateOfJobID { job.duplicateOfJobID = v }
            if let v = salaryMin { job.salaryMin = v }
            if let v = salaryMax { job.salaryMax = v }
            if let v = salaryCurrency { job.salaryCurrency = v }
            if let v = salaryNote { job.salaryNote = v }
            job.updatedAt = Date()
        }
    }

    // MARK: - URL lookup (used by server /api/jobs/by-url)

    /// Find the job_number for the first job whose capture URL matches the given URL.
    /// Returns nil if no match found.
    public func findJobNumber(byURL url: String) async throws -> Int? {
        let captures = try await store.fetch(FetchDescriptor<Capture>())
        guard let capture = captures.first(where: { $0.url == url }),
              let job = capture.job else { return nil }
        return job.jobNumber
    }

    // MARK: - MCP read queries

    public func listJobs(status: String?, limit: Int) async throws -> [JobListRecord] {
        if let statusRaw = status, let jobStatus = JobStatus(rawValue: statusRaw) {
            // Status filter: SwiftData can't predicate on enum types, so fetch sorted then filter
            // in memory. fetchLimit is omitted here because it would count pre-filter rows.
            let descriptor = FetchDescriptor<Job>(
                sortBy: [SortDescriptor(\Job.createdAt, order: .reverse)]
            )
            let all = try await store.fetch(descriptor)
            return Array(all.lazy.filter { $0.status == jobStatus }.prefix(limit))
                .map { JobListRecord(job: $0) }
        } else {
            // No filter: fetchLimit lets SwiftData avoid materialising every row.
            var descriptor = FetchDescriptor<Job>(
                sortBy: [SortDescriptor(\Job.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            let jobs = try await store.fetch(descriptor)
            return jobs.map { JobListRecord(job: $0) }
        }
    }

    public func getJob(byNumber number: Int) async throws -> JobDetailRecord? {
        let descriptor = FetchDescriptor<Job>(
            predicate: #Predicate { $0.jobNumber == number }
        )
        let jobs = try await store.fetch(descriptor)
        return jobs.first.map { JobDetailRecord(job: $0) }
    }

    public func workflowSnapshot() async throws -> WorkflowSnapshot {
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let sites = try await store.fetch(FetchDescriptor<Site>())
        var counts: [String: Int] = [:]
        for job in jobs { counts[job.status.rawValue, default: 0] += 1 }
        return WorkflowSnapshot(jobsTotal: jobs.count, sitesTotal: sites.count, statusCounts: counts)
    }

    // MARK: - Duplicate management

    /// Clear the duplicate relationship for a job, keeping it in the job list.
    /// Clears `duplicateOfJobID` and, if `status` was `.duplicate`, resets it to `.new`
    /// so the job reappears in normal status folders. A non-duplicate status (e.g. `.pursuing`)
    /// is preserved as-is.
    public func unmarkDuplicate(jobID: String) async throws {
        try await store.update(Job.self, predicate: #Predicate { $0.id == jobID }) { job in
            job.duplicateOfJobID = nil
            if job.status == .duplicate {
                job.status = .new
            }
            job.updatedAt = Date()
        }
    }

    // MARK: - Availability

    /// Bulk-mark a set of jobs as expired (e.g. after availability check confirms they're gone).
    public func markExpired(jobIDs: [String]) async throws {
        guard !jobIDs.isEmpty else { return }
        let ids = jobIDs
        try await store.update(Job.self, predicate: #Predicate { ids.contains($0.id) }) { job in
            job.status = .expired
            job.updatedAt = Date()
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
