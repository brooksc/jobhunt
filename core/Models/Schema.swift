import Foundation
import SwiftData

// MARK: - Schema Evolution Policy

//
// Schema policy: SchemaV1 is frozen — do NOT add, remove, or rename
// @Attribute-annotated stored properties in SchemaV1 model classes.
// For any breaking change: (1) create SchemaV2 with a frozen snapshot,
// (2) add a MigrationStage, (3) update JobhuntMigrationPlan.
// Non-breaking additions (new optional properties with nil default) are
// allowed in-place and do NOT require a new version.
//
// This file owns in-app SwiftData schema migration. The standalone `tools/migrator`
// tool handles the separate one-time Electron→SwiftData import and is unrelated.
//
// ## When to create a new VersionedSchema
//
// Create SchemaV2 (etc.) when a model change is NOT backward-compatible with the live store:
//   - Renaming a stored property (SwiftData treats it as delete+add → data loss without a stage)
//   - Changing a property's stored type
//   - Removing a required (non-optional) property
//   - Adding @Attribute(.unique) to a field that already has duplicate values in the live store
//
// Backward-compatible changes that do NOT require a new VersionedSchema:
//   - Adding a new optional property (SwiftData lightweight migration fills nil automatically)
//   - Adding a new model (add it to SchemaV1.models; existing containers gain the new table)
//   - Adding a transient/@Attribute(.ephemeral) property
//   - Adding @Attribute(.unique) to a field on a fresh install (no existing duplicate rows)
//
// ## How to add a SchemaV2
//
//   1. Copy the current version's model files into a SchemaV2 namespace (or use a typealiased
//      snapshot). The VersionedSchema must capture the exact shape the store had at that version.
//   2. Bump the version identifier: Schema.Version(2, 0, 0).
//   3. Add a MigrationStage between V1 and V2 — use .lightweight if SwiftData can infer the
//      mapping automatically; use .custom with willMigrate/didMigrate closures otherwise.
//   4. Add SchemaV2.self to JobhuntMigrationPlan.schemas (order: oldest → newest).
//   5. Add the migration stage to JobhuntMigrationPlan.stages.
//   6. Write a SchemaEvolutionTests test that: creates a V1 container → inserts data →
//      opens it again with the migration plan → asserts data is intact and new fields present.
//
// ## Standalone legacy migrator role
//
// tools/migrator/ is a one-time developer CLI (not shipped in the app) for importing
// legacy Electron jobhunt.db (SQLite) into a fresh SwiftData store. Its README documents
// the supported tables and usage. It is independent of this migration plan and runs only
// once per developer machine.

// MARK: - How V1 is frozen without snapshot types (TASK-368 / TASK-369)

//
// SchemaV1.models points at the live model classes. We deliberately do NOT duplicate all models
// into an immutable `SchemaV1Snapshot` namespace today: there is no V2 yet, so a snapshot would be
// byte-identical to the live models and add ongoing maintenance for zero current benefit. Instead
// the V1 stored shape is frozen by compile-time tripwires in SchemaEvolutionTests:
//   - testSchemaV1StoredPropertyNamesAreStable — fails to compile if a stored property is
//     renamed/removed.
//   - testSchemaV1StoredPropertyTypesAreStable — fails to compile if a stored property's TYPE
//     changes (e.g. Int→String, optional→non-optional).
// Together these make a breaking V1 change impossible to ship unnoticed.
//
// When an actual breaking change lands, that is the moment to (a) snapshot the V1 models into a
// frozen namespace per the "How to add a SchemaV2" steps below, and (b) add a golden file-backed
// old-store migration test (TASK-369) that opens a real pre-change store with the new plan.
//
// MARK: - Schema policy checklist

//
// Changes that DO need a new VersionedSchema + MigrationStage:
//   [x] Rename a stored property
//   [x] Change a stored property's type
//   [x] Remove a non-optional stored property
//   [x] Add @Attribute(.unique) to an existing field that has duplicate values in the live store
//       (must deduplicate rows first via a custom migration stage)
//
// Changes that do NOT need a new VersionedSchema:
//   [ ] Add a new optional stored property (lightweight migration fills nil)
//   [ ] Add a new @Model class to SchemaV1.models
//   [ ] Add a @Relationship property
//   [ ] Add a computed property or method
//   [ ] Add @Attribute(.unique) to a field on a brand-new install (no pre-existing duplicates)
//   [ ] Add @Attribute(.ephemeral) / transient properties

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
            CoverLetter.self,
            SavedSearch.self,
            ApplicationEvidence.self,
            ReferralAttempt.self,
            InterviewRecord.self,
            OfferRecord.self,
            DiscoveryLedgerEntry.self,
            SearchSource.self,
            MarketSweepState.self
        ]
    }
}

public enum JobhuntMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
        // When SchemaV2 is added: [SchemaV1.self, SchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        []
        // When a migration stage is needed:
        // [MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
