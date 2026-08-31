import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for `BackgroundStore.repairRemoteTypesFromExtractedJSON` — the one-time repair for work
/// arrangements the old post-extraction clamp erased (TASK-708). The model's answer survived in
/// `Job.extractedJSON`; this pass reads it back, and re-judges `meetsCriteria` so the restored rows
/// stop bucketing as "arrangement not stated".
final class RepairRemoteTypesTests: XCTestCase {
    private func makeJob(
        number: Int,
        remoteType: RemoteType? = nil,
        location: String? = "Lehi, UT",
        extractedJSON: String? = nil,
        meetsCriteria: Bool? = nil,
        overrides: String? = nil
    ) -> Job {
        let job = Job(jobNumber: number, title: "Product Manager")
        job.remoteType = remoteType
        job.location = location
        job.extractedJSON = extractedJSON
        job.meetsCriteria = meetsCriteria
        job.manualFieldOverridesJSON = overrides
        return job
    }

    private func extraction(_ remoteType: String?) -> String {
        let value = remoteType.map { "\"\($0)\"" } ?? "null"
        return #"{"company":"Acme","title":"Product Manager","remote_type":\#(value)}"#
    }

    /// The user's settings, as the migrator reads them: only fully-remote roles are wanted, which is
    /// the shape that made the old clamp erase every hybrid/onsite answer.
    private func store(
        _ jobs: [Job],
        allowHybrid: Bool = false,
        allowOnsite: Bool = false
    ) async throws -> BackgroundStore {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        try await store.insert(Setting(key: SettingsKey.locationFilterEnabled, value: "true"))
        try await store.insert(Setting(key: SettingsKey.locationAllowRemote, value: "true"))
        try await store.insert(Setting(key: SettingsKey.locationAllowHybrid, value: allowHybrid ? "true" : "false"))
        try await store.insert(Setting(key: SettingsKey.locationAllowOnsite, value: allowOnsite ? "true" : "false"))
        try await store.insertBatch(jobs)
        return store
    }

    private func job(_ store: BackgroundStore, _ number: Int) async throws -> Job {
        let rows = try await store.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == number })
        )
        return try XCTUnwrap(rows.first)
    }

    // MARK: - Restoring

    /// The reported case (job #1424): the clamp nulled a perfectly good "hybrid".
    func testRestoresArrangementFromExtractedJSON() async throws {
        let store = try await store([makeJob(number: 1424, extractedJSON: extraction("hybrid"))])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 1)
        XCTAssertEqual(result.restored[.hybrid], 1)
        XCTAssertEqual(result.skippedUnrecoverable, 0)
        XCTAssertEqual(result.skippedOverridden, 0)

        let v1 = try await job(store, 1424).remoteType

        XCTAssertEqual(v1, .hybrid)
    }

    func testRestoresEachArrangementSeparately() async throws {
        let store = try await store([
            makeJob(number: 1, extractedJSON: extraction("hybrid")),
            makeJob(number: 2, extractedJSON: extraction("onsite")),
            makeJob(number: 3, extractedJSON: extraction("remote"))
        ])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 3)
        XCTAssertEqual(result.restored[.hybrid], 1)
        XCTAssertEqual(result.restored[.onsite], 1)
        XCTAssertEqual(result.restored[.remote], 1)
    }

    // MARK: - What it leaves alone

    /// No `remote_type` key at all — nothing to recover. Inferring one from the location is
    /// `--recompute-criteria`'s job, not this pass's.
    func testJobWithNoRemoteTypeKeyIsUntouched() async throws {
        let store = try await store([makeJob(
            number: 7,
            extractedJSON: #"{"company":"Acme","title":"Product Manager"}"#
        )])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 0)
        XCTAssertEqual(result.skippedUnrecoverable, 1)
        let v2 = try await job(store, 7).remoteType
        XCTAssertNil(v2)
    }

    /// An explicit JSON null, and the literal "unknown", are both "no answer" — `.unknown` and nil
    /// are the same bucket to `criteriaBucket` and `QualityChecker`.
    func testNullAndUnknownAreNotRestored() async throws {
        let store = try await store([
            makeJob(number: 8, extractedJSON: extraction(nil)),
            makeJob(number: 9, extractedJSON: extraction("unknown")),
            makeJob(number: 10, extractedJSON: nil)
        ])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 0)
        XCTAssertEqual(result.skippedUnrecoverable, 3)
    }

    /// Repair, not re-derivation: a job that already states an arrangement keeps it, even when the
    /// stored extraction says something else.
    func testNeverOverwritesAPopulatedArrangement() async throws {
        let store = try await store([makeJob(
            number: 11, remoteType: .onsite, extractedJSON: extraction("remote")
        )])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 0)
        XCTAssertEqual(result.skippedUnrecoverable, 0)
        let v3 = try await job(store, 11).remoteType
        XCTAssertEqual(v3, .onsite)
    }

    /// The user's own edit outranks the restore, and is counted separately.
    func testManualOverrideIsRespected() async throws {
        let store = try await store([makeJob(
            number: 12, extractedJSON: extraction("hybrid"), overrides: #"["remoteType"]"#
        )])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 0)
        XCTAssertEqual(result.skippedOverridden, 1)
        XCTAssertEqual(result.skippedUnrecoverable, 0)
        let v4 = try await job(store, 12).remoteType
        XCTAssertNil(v4)
    }

    /// An override of some *other* field must not block the repair.
    func testUnrelatedOverrideDoesNotBlockRepair() async throws {
        let store = try await store([makeJob(
            number: 13, extractedJSON: extraction("onsite"), overrides: #"["salaryMin","location"]"#
        )])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.restored[.onsite], 1)
        XCTAssertEqual(result.skippedOverridden, 0)
    }

    /// A single unparseable row must be skipped, not abort the whole pass.
    func testMalformedJSONIsSkippedNotThrown() async throws {
        let store = try await store([
            makeJob(number: 14, extractedJSON: "{not json at all"),
            makeJob(number: 15, extractedJSON: "[1, 2, 3]"),
            makeJob(number: 16, extractedJSON: extraction("hybrid"))
        ])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.skippedUnrecoverable, 2)
        XCTAssertEqual(result.restored[.hybrid], 1)
        let v5 = try await job(store, 14).remoteType
        XCTAssertNil(v5)
        let v6 = try await job(store, 16).remoteType
        XCTAssertEqual(v6, .hybrid)
    }

    // MARK: - Criteria verdicts

    /// Without this the arrangement comes back but the job stays in the "not stated" bucket, which
    /// is the entire visible symptom.
    func testMeetsCriteriaIsRecomputedForChangedRows() async throws {
        let store = try await store([
            // Was stored as nil/nil — restoring "hybrid" must produce an explicit false, which moves
            // it out of `.notStated` and into `.doesNotMeet`.
            makeJob(number: 20, extractedJSON: extraction("hybrid"), meetsCriteria: nil),
            // A remote role the settings do allow: restoring flips the stale false to true.
            makeJob(number: 21, location: "Remote - US", extractedJSON: extraction("remote"), meetsCriteria: false)
        ])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 2)
        XCTAssertEqual(result.criteriaChanged, 2)

        let hybrid = try await job(store, 20)
        XCTAssertEqual(hybrid.meetsCriteria, false)
        XCTAssertEqual(
            JobFilterRules.criteriaBucket(meetsCriteria: hybrid.meetsCriteria, remoteType: hybrid.remoteType),
            .doesNotMeet
        )

        let v7 = try await job(store, 21).meetsCriteria

        XCTAssertEqual(v7, true)
    }

    /// A restored row whose verdict was already correct is still restored, but not counted as a
    /// verdict change.
    func testVerdictUnchangedIsNotCounted() async throws {
        let store = try await store([
            makeJob(number: 22, extractedJSON: extraction("hybrid"), meetsCriteria: false)
        ])

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 1)
        XCTAssertEqual(result.criteriaChanged, 0)
    }

    /// With hybrid allowed the same restored value passes the criteria — proving the verdict comes
    /// from the stored settings rather than a hardcoded rule.
    func testVerdictFollowsTheStoredSettings() async throws {
        let store = try await store(
            [makeJob(number: 23, location: "Lehi, UT", extractedJSON: extraction("hybrid"), meetsCriteria: false)],
            allowHybrid: true
        )
        try await store.insert(Setting(key: SettingsKey.preferredLocations, value: "Lehi, UT"))

        let result = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(result.totalRestored, 1)
        let v8 = try await job(store, 23).meetsCriteria
        XCTAssertEqual(v8, true)
    }

    // MARK: - Idempotence

    func testSecondRunIsANoOp() async throws {
        let store = try await store([
            makeJob(number: 30, extractedJSON: extraction("hybrid")),
            makeJob(number: 31, extractedJSON: extraction("onsite")),
            makeJob(number: 32, extractedJSON: extraction(nil)),
            makeJob(number: 33, extractedJSON: extraction("remote"), overrides: #"["remoteType"]"#)
        ])

        let first = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(first.totalRestored, 2)

        let second = try await store.repairRemoteTypesFromExtractedJSON()
        XCTAssertEqual(second.totalRestored, 0)
        XCTAssertEqual(second.criteriaChanged, 0)
        // The unrecoverable and overridden rows are still reported — they are state, not work done.
        XCTAssertEqual(second.skippedUnrecoverable, 1)
        XCTAssertEqual(second.skippedOverridden, 1)

        let v9 = try await job(store, 30).remoteType

        XCTAssertEqual(v9, .hybrid)
        let v10 = try await job(store, 31).remoteType
        XCTAssertEqual(v10, .onsite)
    }

    // MARK: - Parsing helper

    func testExtractedRemoteTypeParsing() {
        XCTAssertEqual(BackgroundStore.extractedRemoteType(#"{"remote_type":"hybrid"}"#), .hybrid)
        XCTAssertEqual(BackgroundStore.extractedRemoteType(#"{"remote_type":" Onsite "}"#), .onsite)
        XCTAssertNil(BackgroundStore.extractedRemoteType(#"{"remote_type":"unknown"}"#))
        XCTAssertNil(BackgroundStore.extractedRemoteType(#"{"remote_type":"work from mars"}"#))
        XCTAssertNil(BackgroundStore.extractedRemoteType(#"{"remote_type":3}"#))
        XCTAssertNil(BackgroundStore.extractedRemoteType("not json"))
        XCTAssertNil(BackgroundStore.extractedRemoteType(nil))
    }

    // MARK: - Arg parsing

    func testMigratorFlagParses() throws {
        guard case .repairRemoteTypes = try XCTUnwrap(parseArgs(["migrator", "--repair-remote-types"])) else {
            return XCTFail("expected .repairRemoteTypes")
        }
        // The operation flags are mutually exclusive (TASK-523).
        XCTAssertNil(parseArgs(["migrator", "--repair-remote-types", "--recompute-criteria"]))
    }
}
