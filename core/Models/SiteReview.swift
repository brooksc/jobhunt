import Foundation
import SwiftData

@Model
public final class SiteReview {
    public var id: String
    public var siteURL: String
    public var siteOrigin: String
    public var pageTitle: String?
    public var reviewedAt: Date
    public var nextReviewAt: Date?
    public var note: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        siteURL: String,
        siteOrigin: String,
        pageTitle: String? = nil,
        reviewedAt: Date = Date(),
        nextReviewAt: Date? = nil,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.siteURL = siteURL
        self.siteOrigin = siteOrigin
        self.pageTitle = pageTitle
        self.reviewedAt = reviewedAt
        self.nextReviewAt = nextReviewAt
        self.note = note
        self.createdAt = createdAt
    }
}
