import Foundation

// MARK: - Application History (TASK-628)

/// One application-contact record for the Application History report / unemployment-benefit job-search
/// log. Built from authoritative Applied history (the `appliedAt` first-Applied timestamp, or the first
/// `status → applied` event for legacy rows), independent of the job's CURRENT status — a job stays in
/// the report after moving to Interview/Offer/Rejected/Passed/Closed/Expired/Archived. ESD employer-
/// contact evidence fields are user-entered and never inferred (empty until Phase 2).
public struct ApplicationRecord: Sendable, Equatable, Identifiable {
    public let jobID: String
    public let jobNumber: Int?
    /// Authoritative first-Applied timestamp; nil = a legacy Applied history with no reliable date.
    public let appliedAt: Date?
    public let company: String?
    public let jobTitle: String?
    public let sourceURL: String
    public let currentStatus: String
    public let notes: String?

    // ESD employer-contact evidence — user-entered, never inferred from a URL (AC #9). Empty in Phase 1.
    public let contactMethod: String?
    public let contactType: String?
    public let employerWebsiteOrEmail: String?
    public let phone: String?
    public let employerAddress: String?
    public let city: String?
    public let state: String?
    public let jobReferenceNumber: String?
    public let applicationResult: String?

    public var id: String { jobID }
    public var hasApplicationDate: Bool { appliedAt != nil }

    public init(
        jobID: String, jobNumber: Int?, appliedAt: Date?, company: String?, jobTitle: String?,
        sourceURL: String, currentStatus: String, notes: String?,
        contactMethod: String? = nil, contactType: String? = nil, employerWebsiteOrEmail: String? = nil,
        phone: String? = nil, employerAddress: String? = nil, city: String? = nil, state: String? = nil,
        jobReferenceNumber: String? = nil, applicationResult: String? = nil
    ) {
        self.jobID = jobID
        self.jobNumber = jobNumber
        self.appliedAt = appliedAt
        self.company = company
        self.jobTitle = jobTitle
        self.sourceURL = sourceURL
        self.currentStatus = currentStatus
        self.notes = notes
        self.contactMethod = contactMethod
        self.contactType = contactType
        self.employerWebsiteOrEmail = employerWebsiteOrEmail
        self.phone = phone
        self.employerAddress = employerAddress
        self.city = city
        self.state = state
        self.jobReferenceNumber = jobReferenceNumber
        self.applicationResult = applicationResult
    }
}

public enum ApplicationHistory {
    /// Pure projection of a job's Applied history so the builder stays SwiftData-free and unit-testable.
    public struct JobInput: Sendable {
        public let jobID: String
        public let jobNumber: Int?
        public let company: String?
        public let title: String?
        public let sourceURL: String
        public let currentStatus: String
        public let notes: String?
        public let appliedAt: Date?
        /// `occurredAt` of every `status → applied` transition event — the legacy fallback for rows
        /// captured before `appliedAt` existed.
        public let appliedEventDates: [Date]

        public init(
            jobID: String, jobNumber: Int?, company: String?, title: String?, sourceURL: String,
            currentStatus: String, notes: String?, appliedAt: Date?, appliedEventDates: [Date]
        ) {
            self.jobID = jobID
            self.jobNumber = jobNumber
            self.company = company
            self.title = title
            self.sourceURL = sourceURL
            self.currentStatus = currentStatus
            self.notes = notes
            self.appliedAt = appliedAt
            self.appliedEventDates = appliedEventDates
        }
    }

    /// Current statuses that imply the user previously applied (legacy fallback when there's neither an
    /// `appliedAt` nor an applied event). Conservative: only outcomes that follow an application.
    static let appliedImplyingStatuses: Set<String> = ["applied", "interview", "offer", "rejected"]

    static func everApplied(_ job: JobInput) -> Bool {
        job.appliedAt != nil || !job.appliedEventDates.isEmpty || appliedImplyingStatuses.contains(job.currentStatus)
    }

    /// The authoritative first-Applied timestamp: `appliedAt` (set once on the first Applied transition),
    /// else the earliest `status → applied` event; nil when only the current status implies it (AC #3/#4).
    static func firstAppliedAt(_ job: JobInput) -> Date? {
        job.appliedAt ?? job.appliedEventDates.min()
    }

    /// Build the report: one record per job with an authoritative Applied history, newest application
    /// first; missing-date rows sort last; ties broken by job number then id (deterministic — AC #5/#10).
    public static func build(jobs: [JobInput]) -> [ApplicationRecord] {
        jobs.filter(everApplied).map { job in
            ApplicationRecord(
                jobID: job.jobID, jobNumber: job.jobNumber, appliedAt: firstAppliedAt(job),
                company: job.company, jobTitle: job.title, sourceURL: job.sourceURL,
                currentStatus: job.currentStatus, notes: job.notes
            )
        }.sorted { lhs, rhs in
            let lDate = lhs.appliedAt ?? .distantPast // missing dates sort last in a newest-first order
            let rDate = rhs.appliedAt ?? .distantPast
            if lDate != rDate { return lDate > rDate }
            let lNum = lhs.jobNumber ?? Int.max
            let rNum = rhs.jobNumber ?? Int.max
            if lNum != rNum { return lNum < rNum }
            return lhs.jobID < rhs.jobID
        }
    }

    /// The Saturday ending the Sunday–Saturday Washington claim week containing `date` (start of that
    /// Saturday), in `calendar`'s time zone (AC #6). `.weekday` is 1=Sun…7=Sat regardless of locale.
    public static func claimWeekEnding(for date: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 7 - weekday, to: day) ?? day
    }

    /// Records whose application date falls in the inclusive `[start, end]` range (whole days), plus all
    /// missing-date records (they need attention and shouldn't silently vanish from a filtered view).
    public static func filter(_ records: [ApplicationRecord], from start: Date?, to end: Date?,
                              calendar: Calendar = .current) -> [ApplicationRecord] {
        records.filter { record in
            guard let applied = record.appliedAt else { return true }
            let day = calendar.startOfDay(for: applied)
            if let start, day < calendar.startOfDay(for: start) { return false }
            if let end, day > calendar.startOfDay(for: end) { return false }
            return true
        }
    }
}
