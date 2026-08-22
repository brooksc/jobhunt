import Foundation
import SwiftData

/// The persistence rules for what happens to an application after it's sent: referral outreach,
/// interview rounds, and an offer — each with the timeline event that mirrors it (TASK-686).
///
/// These rules are subtle and were previously interleaved with the rest of `BackgroundStore`, a
/// 2,400-line file that every domain in the app writes through. The subtlety is the pairing: a
/// milestone record and its timeline event have to be created, corrected and deleted together, or the
/// Timeline shows outreach that no longer exists and the Dashboard counts it forever. Collecting them
/// here means that pairing can be read — and changed — in one place.
///
/// **Owns no context and no actor.** Every function takes the caller's `ModelContext` and runs on the
/// caller's isolation, so this stays inside `BackgroundStore`'s single transaction rather than opening
/// a second writer against a store that permits exactly one. `save()` is left to the caller for the
/// same reason: a milestone write is frequently part of a larger one.
enum MilestonePersistence {
    // MARK: - Referral outreach (TASK-630)

    /// The deterministic ids of the two timeline events a referral attempt can own. Deriving them from
    /// the attempt id (rather than a random UUID) makes the milestone log idempotent — reverting a
    /// status and advancing to it again can't re-count it — and lets `deleteReferralAttempt` take the
    /// events with it (TASK-644 review).
    static func referralEventID(_ attemptID: String, _ milestone: String) -> String {
        "referral-\(milestone)-\(attemptID)"
    }

    /// Record a new referral attempt or update an existing one (by `input.id`). Logs at most one
    /// structured `referral` timeline event per milestone (AC #12) so the Dashboard counts each outreach
    /// once (AC #17); the `not_pursuing` marker never emits one.
    @discardableResult
    static func recordReferralAttempt(_ input: ReferralAttemptInput, in context: ModelContext) throws -> String {
        let isMarker = input.outcome == ReferralOutcome.notApplicable.rawValue
        // A user-facing write against a job that's gone must surface, not silently persist an orphan
        // attempt plus an unlinked timeline event (the TASK-578 `requireJob` convention).
        let jid = input.jobID
        guard let job = try context.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid })
        ).first else { throw BackgroundStoreError.notFound(input.jobID) }

        /// Insert a milestone event unless it (or its pre-deterministic-id equivalent) already exists.
        func logReferralEvent(milestone: String, note: String, occurredAt: Date) throws {
            let eventID = referralEventID(input.id ?? "", milestone)
            let byID = try context.fetch(FetchDescriptor<JobEvent>(predicate: #Predicate { $0.id == eventID }))
            guard byID.isEmpty else { return }
            // Attempts recorded before deterministic ids carry a random-id event; match those on their
            // exact note text so an edit doesn't append a second copy.
            let legacyNote = note
            let legacy = try context.fetch(
                FetchDescriptor<JobEvent>(predicate: #Predicate { $0.note == legacyNote && $0.job?.id == jid })
            )
            guard legacy.isEmpty else { return }
            let event = JobEvent(id: eventID, eventType: "referral", note: note, occurredAt: occurredAt)
            event.job = job
            context.insert(event)
        }
        // "New" is decided by whether the row already exists, not by a nil id — so an editor that keeps
        // a stable id and re-saves (e.g. after a transient failure, or a double Save) upserts one record
        // instead of duplicating it (TASK-644 review #7).
        var existing: ReferralAttempt?
        if let id = input.id {
            existing = try context.fetch(
                FetchDescriptor<ReferralAttempt>(predicate: #Predicate { $0.id == id })
            ).first
        }
        let isNew = existing == nil
        let attempt: ReferralAttempt
        if let existing {
            attempt = existing
        } else {
            attempt = ReferralAttempt(
                id: input.id ?? UUID().uuidString,
                jobID: input.jobID,
                recipientName: input.recipientName,
                outcome: input.outcome
            )
            context.insert(attempt)
        }
        // Clamp the milestones into chronological order. The editor bounds its pickers, but the store is
        // the layer any future MCP/server tool would hit, and an inverted timeline corrupts the follow-up
        // staleness math and row sorting (TASK-644 review #1).
        let requestedAt = input.requestedAt
        let respondedAt = input.respondedAt.map { max($0, requestedAt) }
        let reachedAt = respondedAt ?? requestedAt
        attempt.jobID = input.jobID
        attempt.recipientName = input.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
        attempt.recipientIdentifier = cleaned(input.recipientIdentifier)
        attempt.channel = cleaned(input.channel)
        attempt.note = cleaned(input.note)
        attempt.requestedAt = requestedAt
        attempt.respondedAt = respondedAt
        attempt.submittedAt = input.submittedAt.map { max($0, reachedAt) }
        attempt.declinedAt = input.declinedAt.map { max($0, reachedAt) }
        attempt.outcome = input.outcome
        // Recording real outreach supersedes a job-level "N/A — no referral possible" marker; leaving it
        // behind strands the toggle checked-and-disabled and silently drops the job from the outreach
        // nudges once the real attempts are deleted (TASK-644 review #2).
        if !isMarker { try clearReferralMarker(jobID: input.jobID, in: context) }

        if !isMarker {
            let isSubmitted = input.outcome == ReferralOutcome.submitted.rawValue
            // One event per genuine milestone. A brand-new attempt recorded as *already* Submitted logs
            // only the milestone — logging both "requested" and "submitted" counted a single outreach
            // twice in Today's recap (TASK-644 review #3).
            if isNew, !isSubmitted {
                try logReferralEvent(
                    milestone: "req", note: "Referral requested — \(attempt.recipientName)",
                    occurredAt: attempt.requestedAt
                )
            }
            if isSubmitted {
                try logReferralEvent(
                    milestone: "sub", note: "Referral submitted — \(attempt.recipientName)",
                    occurredAt: attempt.submittedAt ?? Date()
                )
            }
        }
        return attempt.id
    }

    /// Delete a referral attempt *and* the timeline events it owns — otherwise a mistaken outreach stays
    /// in the job's Timeline and keeps counting toward the Referrals recap with no way to remove it
    /// (TASK-644 review #4).
    ///
    /// - Returns: whether anything was deleted, so the caller can skip a pointless save.
    @discardableResult
    static func deleteReferralAttempt(id: String, in context: ModelContext) throws -> Bool {
        let attemptID = id
        guard let existing = try context.fetch(
            FetchDescriptor<ReferralAttempt>(predicate: #Predicate { $0.id == attemptID })
        ).first else { return false }
        let jid = existing.jobID
        let notes = [
            "Referral requested — \(existing.recipientName)",
            "Referral submitted — \(existing.recipientName)"
        ]
        let ids = [referralEventID(attemptID, "req"), referralEventID(attemptID, "sub")]
        let events = try context.fetch(
            FetchDescriptor<JobEvent>(predicate: #Predicate { $0.job?.id == jid })
        )
        for event in events where ids.contains(event.id) || (event.note.map { notes.contains($0) } ?? false) {
            context.delete(event)
        }
        context.delete(existing)
        return true
    }

    /// Remove any job-level N/A markers for a job.
    static func clearReferralMarker(jobID: String, in context: ModelContext) throws {
        let jid = jobID
        let marker = ReferralOutcome.notApplicable.rawValue
        try context.fetch(
            FetchDescriptor<ReferralAttempt>(predicate: #Predicate { $0.jobID == jid && $0.outcome == marker })
        ).forEach { context.delete($0) }
    }

    /// Set (or clear) the recipient-less "N/A — no referral possible" marker for a job (AC #3, TASK-644).
    /// Setting it is ignored when real outreach exists — the two states are mutually exclusive.
    static func setReferralNotApplicable(jobID: String, _ notApplicable: Bool, in context: ModelContext) throws {
        let jid = jobID
        let marker = ReferralOutcome.notApplicable.rawValue
        if notApplicable {
            let all = try context.fetch(
                FetchDescriptor<ReferralAttempt>(predicate: #Predicate { $0.jobID == jid })
            )
            guard !all.contains(where: { $0.outcome != marker }) else { return } // real outreach wins
            if !all.contains(where: { $0.outcome == marker }) {
                context.insert(ReferralAttempt(jobID: jid, recipientName: "", outcome: marker))
            }
        } else {
            try clearReferralMarker(jobID: jid, in: context)
        }
    }

    /// Delete every referral attempt (and N/A marker) belonging to a job — used when the job itself is
    /// deleted, since `jobID` is a plain key with no cascading relationship.
    @discardableResult
    static func deleteReferralAttempts(jobID: String, in context: ModelContext) throws -> Bool {
        let jid = jobID
        let attempts = try context.fetch(
            FetchDescriptor<ReferralAttempt>(predicate: #Predicate { $0.jobID == jid })
        )
        guard !attempts.isEmpty else { return false }
        attempts.forEach { context.delete($0) }
        return true
    }

    /// Delete referral attempts whose job no longer exists. `ReferralAttempt` is keyed by `jobID` with no
    /// SwiftData relationship, so deleting a job leaves its attempts (and N/A marker) behind (TASK-644
    /// review). Returns the number removed.
    static func pruneOrphanReferralAttempts(in context: ModelContext) throws -> Int {
        let attempts = try context.fetch(FetchDescriptor<ReferralAttempt>())
        guard !attempts.isEmpty else { return 0 }
        let liveIDs = try Set(context.fetch(FetchDescriptor<Job>()).map(\.id))
        let orphans = attempts.filter { !liveIDs.contains($0.jobID) }
        orphans.forEach { context.delete($0) }
        return orphans.count
    }

    // MARK: - Interview & offer milestones (TASK-501)

    /// Record or update an interview, logging one timeline event per interview so the Timeline shows the
    /// round rather than a freeform note. Follows the referral conventions: the job must exist, the
    /// event id is derived from the record so re-saving can't duplicate it, and delete takes it with it.
    @discardableResult
    static func recordInterview(_ input: InterviewInput, in context: ModelContext) throws -> String {
        let jid = input.jobID
        guard let job = try context.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid })
        ).first else { throw BackgroundStoreError.notFound(input.jobID) }

        let record: InterviewRecord
        if let id = input.id, let existing = try context.fetch(
            FetchDescriptor<InterviewRecord>(predicate: #Predicate { $0.id == id })
        ).first {
            record = existing
        } else {
            record = InterviewRecord(id: input.id ?? UUID().uuidString, jobID: input.jobID)
            context.insert(record)
        }
        record.jobID = input.jobID
        record.scheduledAt = input.scheduledAt
        record.kind = input.kind
        record.interviewer = cleaned(input.interviewer)
        record.location = cleaned(input.location)
        record.note = cleaned(input.note)

        let label = (InterviewKind(rawValue: input.kind) ?? .other).label
        try upsertMilestoneEvent(
            id: "interview-\(record.id)", eventType: "interview", job: job,
            note: record.interviewer.map { "\(label) — \($0)" } ?? label,
            occurredAt: record.scheduledAt, in: context
        )
        return record.id
    }

    @discardableResult
    static func deleteInterview(id: String, in context: ModelContext) throws -> Bool {
        let rid = id
        guard let existing = try context.fetch(
            FetchDescriptor<InterviewRecord>(predicate: #Predicate { $0.id == rid })
        ).first else { return false }
        try deleteMilestoneEvent(id: "interview-\(rid)", in: context)
        context.delete(existing)
        return true
    }

    /// Record or update the job's offer (at most one per job — an existing offer is updated).
    @discardableResult
    static func recordOffer(_ input: OfferInput, in context: ModelContext) throws -> String {
        let jid = input.jobID
        guard let job = try context.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid })
        ).first else { throw BackgroundStoreError.notFound(input.jobID) }

        let existing = try context.fetch(
            FetchDescriptor<OfferRecord>(predicate: #Predicate { $0.jobID == jid })
        ).first
        let record: OfferRecord
        if let existing {
            record = existing
        } else {
            record = OfferRecord(id: input.id ?? UUID().uuidString, jobID: input.jobID)
            context.insert(record)
        }
        record.offeredAt = input.offeredAt
        record.title = cleaned(input.title)
        record.baseSalary = input.baseSalary
        record.additionalComp = cleaned(input.additionalComp)
        // A decision deadline before the offer date is nonsense — clamp rather than persist it.
        record.decisionBy = input.decisionBy.map { max($0, input.offeredAt) }
        record.note = cleaned(input.note)

        let summary = record.baseSalary.map { "Offer — \(record.title ?? "role"), \($0.formatted())" }
            ?? "Offer — \(record.title ?? "role")"
        try upsertMilestoneEvent(
            id: "offer-\(record.id)", eventType: "offer", job: job, note: summary,
            occurredAt: record.offeredAt, in: context
        )
        return record.id
    }

    @discardableResult
    static func deleteOffer(id: String, in context: ModelContext) throws -> Bool {
        let rid = id
        guard let existing = try context.fetch(
            FetchDescriptor<OfferRecord>(predicate: #Predicate { $0.id == rid })
        ).first else { return false }
        try deleteMilestoneEvent(id: "offer-\(rid)", in: context)
        context.delete(existing)
        return true
    }

    /// Delete every interview and offer belonging to a job — cascaded on job delete, since these are
    /// keyed by `jobID` with no relationship.
    @discardableResult
    static func deleteMilestones(jobID: String, in context: ModelContext) throws -> Bool {
        let jid = jobID
        let interviews = try context.fetch(
            FetchDescriptor<InterviewRecord>(predicate: #Predicate { $0.jobID == jid })
        )
        let offers = try context.fetch(
            FetchDescriptor<OfferRecord>(predicate: #Predicate { $0.jobID == jid })
        )
        guard !interviews.isEmpty || !offers.isEmpty else { return false }
        for interview in interviews {
            try deleteMilestoneEvent(id: "interview-\(interview.id)", in: context)
            context.delete(interview)
        }
        for offer in offers {
            try deleteMilestoneEvent(id: "offer-\(offer.id)", in: context)
            context.delete(offer)
        }
        return true
    }

    // MARK: - Shared

    static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Insert or update the single timeline event mirroring a milestone record, so editing the record
    /// corrects the Timeline entry instead of appending a second one.
    static func upsertMilestoneEvent(
        id: String, eventType: String, job: Job, note: String, occurredAt: Date, in context: ModelContext
    ) throws {
        let eid = id
        if let event = try context.fetch(
            FetchDescriptor<JobEvent>(predicate: #Predicate { $0.id == eid })
        ).first {
            event.note = note
            event.occurredAt = occurredAt
            return
        }
        let event = JobEvent(id: id, eventType: eventType, note: note, occurredAt: occurredAt)
        event.job = job
        context.insert(event)
    }

    static func deleteMilestoneEvent(id: String, in context: ModelContext) throws {
        let eid = id
        try context.fetch(FetchDescriptor<JobEvent>(predicate: #Predicate { $0.id == eid }))
            .forEach { context.delete($0) }
    }
}
