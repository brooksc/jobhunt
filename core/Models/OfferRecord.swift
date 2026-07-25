import Foundation
import SwiftData

/// The offer for a job (TASK-501) — structured so compensation and the decision deadline are real
/// fields rather than buried in freeform notes. Keyed by `jobID` with no relationship, like
/// `ReferralAttempt`. A job holds at most one offer; the store upserts on `jobID`.
@Model
public final class OfferRecord {
    @Attribute(.unique) public var id: String
    public var jobID: String
    /// When the offer was made.
    public var offeredAt: Date
    /// The title actually offered — often differs from the posting's title.
    public var title: String?
    /// Annual base salary. Stored as a whole-currency integer, consistent with `Job.salaryMin/Max`.
    public var baseSalary: Int?
    /// Equity / bonus / sign-on, kept as text since the shape varies wildly.
    public var additionalComp: String?
    /// When a decision is due — drives the "offer expiring" nudge.
    public var decisionBy: Date?
    public var note: String?

    public init(
        id: String = UUID().uuidString, jobID: String, offeredAt: Date = Date(), title: String? = nil,
        baseSalary: Int? = nil, additionalComp: String? = nil, decisionBy: Date? = nil, note: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.offeredAt = offeredAt
        self.title = title
        self.baseSalary = baseSalary
        self.additionalComp = additionalComp
        self.decisionBy = decisionBy
        self.note = note
    }
}

/// Sendable payload for recording/editing an offer across the store actor.
public struct OfferInput: Sendable {
    public let id: String?
    public let jobID: String
    public let offeredAt: Date
    public let title: String?
    public let baseSalary: Int?
    public let additionalComp: String?
    public let decisionBy: Date?
    public let note: String?

    public init(
        id: String? = nil, jobID: String, offeredAt: Date, title: String? = nil, baseSalary: Int? = nil,
        additionalComp: String? = nil, decisionBy: Date? = nil, note: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.offeredAt = offeredAt
        self.title = title
        self.baseSalary = baseSalary
        self.additionalComp = additionalComp
        self.decisionBy = decisionBy
        self.note = note
    }
}
