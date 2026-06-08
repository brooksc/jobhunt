import Foundation
import SwiftData

public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Capture.self,
            Job.self,
            JobEvent.self,
            SiteReview.self,
            DuplicateDecision.self,
            Setting.self,
            JobAction.self,
            DataQualityReview.self,
            Site.self,
            Resume.self,
            JobFitScore.self,
            LLMRequest.self,
            LLMRequestAttempt.self,
            Contact.self,
            CoverLetter.self
        ]
    }
}

public enum JobhuntMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
