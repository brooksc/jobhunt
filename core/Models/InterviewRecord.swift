import Foundation
import SwiftData

/// One scheduled interview for a job (TASK-501). Like `ReferralAttempt` it's keyed by `jobID` with no
/// SwiftData relationship, so the frozen `Job` model is untouched (a new model in `SchemaV1.models` is
/// a non-breaking change). A job can hold many interviews — a screen, a technical round, an onsite.
@Model
public final class InterviewRecord {
    @Attribute(.unique) public var id: String
    public var jobID: String
    /// When the interview is (or was) scheduled.
    public var scheduledAt: Date
    /// One of `InterviewKind`'s raw values. Stored as a string so an unknown value from an older build
    /// degrades to "Interview" rather than failing to load.
    public var kind: String
    public var interviewer: String?
    /// Free text — a room, a video link, "phone", etc.
    public var location: String?
    public var note: String?

    public init(
        id: String = UUID().uuidString, jobID: String, scheduledAt: Date = Date(),
        kind: String = InterviewKind.screen.rawValue, interviewer: String? = nil,
        location: String? = nil, note: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.scheduledAt = scheduledAt
        self.kind = kind
        self.interviewer = interviewer
        self.location = location
        self.note = note
    }
}

/// The round an interview represents. Ordered as a typical loop progresses.
public enum InterviewKind: String, Sendable, CaseIterable {
    case screen
    case hiringManager = "hiring_manager"
    case technical
    case panel
    case onsite
    case final
    case other

    public var label: String {
        switch self {
        case .screen: "Recruiter screen"
        case .hiringManager: "Hiring manager"
        case .technical: "Technical"
        case .panel: "Panel"
        case .onsite: "Onsite"
        case .final: "Final"
        case .other: "Interview"
        }
    }
}

/// Sendable payload for recording/editing an interview across the store actor.
public struct InterviewInput: Sendable {
    public let id: String?
    public let jobID: String
    public let scheduledAt: Date
    public let kind: String
    public let interviewer: String?
    public let location: String?
    public let note: String?

    public init(
        id: String? = nil, jobID: String, scheduledAt: Date, kind: String,
        interviewer: String? = nil, location: String? = nil, note: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.scheduledAt = scheduledAt
        self.kind = kind
        self.interviewer = interviewer
        self.location = location
        self.note = note
    }
}
