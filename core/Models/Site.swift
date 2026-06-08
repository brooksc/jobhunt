import Foundation
import SwiftData

@Model
public final class Site {
    public var id: String
    public var origin: String
    public var url: String
    public var companyName: String?
    public var companyWebsite: String?
    public var jobsURL: String?
    public var companyDescription: String
    public var pageTitle: String
    public var intervalDays: Int
    public var lastReviewedAt: Date?
    public var nextReviewAt: Date?
    public var note: String
    public var state: SiteState
    public var addedAt: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        origin: String,
        url: String,
        companyName: String? = nil,
        companyWebsite: String? = nil,
        jobsURL: String? = nil,
        companyDescription: String = "",
        pageTitle: String = "",
        intervalDays: Int = 14,
        lastReviewedAt: Date? = nil,
        nextReviewAt: Date? = nil,
        note: String = "",
        state: SiteState = .notReviewed,
        addedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.origin = origin
        self.url = url
        self.companyName = companyName
        self.companyWebsite = companyWebsite
        self.jobsURL = jobsURL
        self.companyDescription = companyDescription
        self.pageTitle = pageTitle
        self.intervalDays = intervalDays
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
        self.note = note
        self.state = state
        self.addedAt = addedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
