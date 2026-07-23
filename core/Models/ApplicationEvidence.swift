import Foundation
import SwiftData

/// User-entered ESD employer-contact evidence for one applied job (TASK-628). Kept SEPARATE from `Job`
/// so recording evidence never touches extracted job facts, and referenced by `jobID` (not a SwiftData
/// relationship) so the frozen `Job` model is untouched. Added as a new model to `SchemaV1.models`
/// (a non-breaking, lightweight-migration change).
@Model
public final class ApplicationEvidence {
    /// The `Job.id` this evidence belongs to.
    @Attribute(.unique) public var jobID: String
    public var updatedAt: Date

    /// A user-supplied application date for a legacy row that has no reliable `appliedAt`. Overrides the
    /// missing timestamp in the report without rewriting the job's own history (AC #4).
    public var correctedAppliedAt: Date?

    // ESD employer-contact log fields (AC #8) — all optional, all user-entered, never inferred.
    public var contactMethod: String?
    public var contactType: String?
    public var employerWebsiteOrEmail: String?
    public var phone: String?
    public var employerAddress: String?
    public var city: String?
    public var state: String?
    public var jobReferenceNumber: String?
    public var applicationResult: String?

    public init(
        jobID: String, updatedAt: Date = Date(), correctedAppliedAt: Date? = nil,
        contactMethod: String? = nil, contactType: String? = nil, employerWebsiteOrEmail: String? = nil,
        phone: String? = nil, employerAddress: String? = nil, city: String? = nil, state: String? = nil,
        jobReferenceNumber: String? = nil, applicationResult: String? = nil
    ) {
        self.jobID = jobID
        self.updatedAt = updatedAt
        self.correctedAppliedAt = correctedAppliedAt
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

/// Sendable payload for upserting `ApplicationEvidence` across the store actor boundary (TASK-628).
public struct ApplicationEvidenceInput: Sendable {
    public let jobID: String
    public let correctedAppliedAt: Date?
    public let contactMethod: String?
    public let contactType: String?
    public let employerWebsiteOrEmail: String?
    public let phone: String?
    public let employerAddress: String?
    public let city: String?
    public let state: String?
    public let jobReferenceNumber: String?
    public let applicationResult: String?

    public init(
        jobID: String, correctedAppliedAt: Date? = nil, contactMethod: String? = nil,
        contactType: String? = nil, employerWebsiteOrEmail: String? = nil, phone: String? = nil,
        employerAddress: String? = nil, city: String? = nil, state: String? = nil,
        jobReferenceNumber: String? = nil, applicationResult: String? = nil
    ) {
        self.jobID = jobID
        self.correctedAppliedAt = correctedAppliedAt
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
