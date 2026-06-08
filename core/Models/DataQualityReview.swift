import Foundation
import SwiftData

@Model
public final class DataQualityReview {
    public var reviewedAt: Date
    public var note: String

    public var job: Job?

    public init(reviewedAt: Date = Date(), note: String = "") {
        self.reviewedAt = reviewedAt
        self.note = note
    }
}
