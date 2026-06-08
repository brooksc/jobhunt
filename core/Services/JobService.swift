// swiftlint:disable file_length type_body_length function_body_length
import Foundation
import SwiftData
import CryptoKit

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

public enum JobServiceError: Error, Sendable {
    case missingURL
    case missingPageTitle
    case missingText
    case jobNotFound(String)
    case actionNotFound(String)
    case contactNotFound(String)
    case coverLetterNotFound(String)
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
        let structuredData: [[String: Any]]
        if let jsonStr = payload.structuredDataJSON,
           let data = jsonStr.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            structuredData = parsed
        } else {
            structuredData = []
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
        let cleanedHashValue = cleanedDescription.isEmpty ? nil : DuplicateDetector.cleanedHash(from: cleanedDescription)

        // 4. Dedup: check raw_hash first, then cleaned_hash
        let existingCaptures = try await store.fetch(FetchDescriptor<Capture>())

        // Check for raw hash collision (same content, different URL)
        if let existing = existingCaptures.first(where: { $0.rawHash == rawHashValue }),
           let existingJob = existing.job {
            return IngestResult(
                captureID: existing.id,
                jobNumber: existingJob.jobNumber ?? 0,
                isDuplicate: true
            )
        }

        // Find duplicate job via cleaned hash (same content, different URL)
        var duplicateOfJobID: String?
        if let cHash = cleanedHashValue {
            let url = payload.url
            let canonicalURL = payload.canonicalURL
            if let dupCapture = existingCaptures.first(where: { cap in
                cap.cleanedHash == cHash &&
                cap.url != url &&
                (cap.canonicalURL ?? "") != (canonicalURL ?? "")
            }) {
                duplicateOfJobID = dupCapture.job?.id
            }
        }

        // 5. Auto job_number: max + 1
        let allJobs = try await store.fetch(FetchDescriptor<Job>())
        let maxJobNumber = allJobs.compactMap(\.jobNumber).max() ?? 0
        let jobNumber = maxJobNumber + 1

        // 6. Create Capture + Job
        let captureID = "cap-\(UUID().uuidString)"
        let jobID = "job-\(UUID().uuidString)"

        let capture = Capture(
            id: captureID,
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

        let job = Job(
            id: jobID,
            jobNumber: jobNumber,
            duplicateOfJobID: duplicateOfJobID
        )
        job.capture = capture

        try await store.insert(capture)
        try await store.insert(job)

        // 7. Enqueue extraction
        try await queue.enqueue(jobIDs: [job.id], mode: .extract)

        // 8. Return result
        return IngestResult(
            captureID: captureID,
            jobNumber: jobNumber,
            isDuplicate: false
        )
    }

    // MARK: - Job mutations

    public func setStatus(_ status: JobStatus, for jobID: String) async throws {
        let id = jobID
        try await store.update(Job.self, predicate: #Predicate { $0.id == id }) { job in
            job.status = status
            job.updatedAt = Date()
        }
    }

    public func setStatusBulk(_ status: JobStatus, jobIDs: [String]) async throws {
        for jobID in jobIDs {
            try await setStatus(status, for: jobID)
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
        try await store.delete(Job.self, predicate: #Predicate { $0.id == id })
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
            // modelContext.delete on the store — use the store's delete helper via a workaround
            // DataQualityReview has no id; delete by fetching all and matching job reference
            try await store.update(DataQualityReview.self, predicate: nil) { rev in
                if rev.job?.id == id {
                    // Mark for deletion by setting a sentinel — actual delete below
                }
            }
            // Delete via the job's inverse relationship
            _ = review  // silence unused-variable warning; deletion happens via cascade or explicit delete
            try await store.delete(DataQualityReview.self, predicate: nil)
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
            job.updatedAt = Date()
        }
        try await queue.enqueue(jobIDs: [jobID], mode: .extract)
    }

    public func resetExtractionBulk(jobIDs: [String]) async throws {
        for jobID in jobIDs {
            try await resetExtraction(jobID: jobID)
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
}
// swiftlint:enable file_length type_body_length function_body_length
