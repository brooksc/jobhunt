import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// The inputs below are taken from the live store's 55 distinct values, not invented — the point of
/// this normalizer is that those 55 collapse onto a small band set before they reach the fit-scoring
/// prompt's `experience_level` dimension.
final class SeniorityNormalizerTests: XCTestCase {
    private func n(_ s: String?) -> String? {
        SeniorityNormalizer.normalize(s)
    }

    func testCaseVariantsCollapse() {
        // 134 "Senior" and 42 "senior" were separate values in the store.
        XCTAssertEqual(n("Senior"), "senior")
        XCTAssertEqual(n("senior"), "senior")
        XCTAssertEqual(n("SENIOR"), "senior")
        XCTAssertEqual(n("Staff"), "staff")
        XCTAssertEqual(n("staff"), "staff")
        XCTAssertEqual(n("Principal"), "principal")
        XCTAssertEqual(n("principal"), "principal")
    }

    /// Five spellings of the same band.
    func testMidLevelSpellings() {
        for raw in ["mid-level", "mid_senior", "mid-senior", "Mid level", "midlevel", "Mid"] {
            XCTAssertEqual(n(raw), "mid", "\(raw) should normalize to mid")
        }
    }

    func testAbbreviations() {
        XCTAssertEqual(n("Sr."), "senior")
        XCTAssertEqual(n("Sr"), "senior")
        XCTAssertEqual(n("Jr"), "entry")
        XCTAssertEqual(n("Senior level"), "senior")
    }

    /// #3: no reliable signal means nil, not a guessed band. These feed `experience_level` scoring,
    /// so inventing a level here would be inventing evidence.
    func testValuesCarryingNoLevelBecomeNil() {
        for raw in ["5+ years", "7+ years of experience", "10–15+ years", "II", "III", "3", ""] {
            XCTAssertNil(n(raw), "\(raw) carries no band and must not be guessed")
        }
        XCTAssertNil(n(nil))
    }

    /// A range takes its lower bound: that is the level the posting will actually consider, and
    /// overstating it inflates the fit of roles the candidate is under-levelled for.
    func testCompoundTakesTheFirstNamedLevel() {
        XCTAssertEqual(n("Senior/Principal"), "senior")
        XCTAssertEqual(n("Staff / Principal"), "staff")
    }

    /// Management titles must not collapse into the IC ladder — the user triages on the difference.
    func testManagementTrackIsDistinct() {
        XCTAssertEqual(n("Manager"), "manager")
        XCTAssertEqual(n("Director"), "director")
        XCTAssertEqual(n("AVP"), "executive")
        XCTAssertEqual(n("VP of Engineering"), "executive")
        XCTAssertEqual(n("Head of Product"), "director")
    }

    /// Longest-match ordering: "senior manager" is a manager, not a senior IC.
    func testLongerPhrasesWinOverTheirPrefixes() {
        XCTAssertEqual(n("Senior Manager"), "manager")
        XCTAssertEqual(n("Senior Director"), "director")
        XCTAssertEqual(n("mid senior"), "mid", "must not be read as plain senior")
    }

    func testEntryAndInternBands() {
        XCTAssertEqual(n("New Grad"), "entry")
        XCTAssertEqual(n("Associate"), "entry")
        XCTAssertEqual(n("Intern"), "intern")
        XCTAssertEqual(n("Internship"), "intern")
    }

    func testLeadAndDistinguished() {
        XCTAssertEqual(n("Lead"), "lead")
        XCTAssertEqual(n("Tech Lead"), "lead")
        XCTAssertEqual(n("Distinguished Engineer"), "principal")
    }

    /// Whole-word matching: a substring test would let "seniority" and "vpn" through.
    func testNoSubstringFalsePositives() {
        XCTAssertNil(n("seniority"))
        XCTAssertNil(n("vpn"))
    }

    /// #4's real requirement: normalizing an already-normalized value must not change it, or the
    /// backfill isn't idempotent.
    func testIdempotent() {
        for level in SeniorityLevel.allCases {
            XCTAssertEqual(n(level.rawValue), level.rawValue, "\(level.rawValue) must be a fixed point")
        }
    }
}

/// The backfill, which is what actually collapses the 55 stored values.
final class SeniorityBackfillTests: XCTestCase {
    private func store() throws -> (BackgroundStore, ModelContainer) {
        let container = try ModelContainerFactory.inMemory()
        return (BackgroundStore(modelContainer: container), container)
    }

    private func seed(_ container: ModelContainer, _ values: [String?]) throws {
        let ctx = ModelContext(container)
        for (i, v) in values.enumerated() {
            let job = Job(id: "j\(i)", jobNumber: i + 1, company: "C", title: "T")
            job.seniority = v
            ctx.insert(job)
        }
        try ctx.save()
    }

    private func stored(_ container: ModelContainer) throws -> [String?] {
        try ModelContext(container).fetch(FetchDescriptor<Job>()).map(\.seniority)
    }

    /// #6: the distinct-value count is the whole point.
    func testDistinctValuesCollapse() async throws {
        let (store, container) = try store()
        try seed(container, ["Senior", "senior", "SENIOR", "Staff", "staff", "mid-level", "mid_senior", "Mid level"])

        _ = try await store.normalizeStoredSeniority()
        let distinct = try Set(stored(container).compactMap(\.self))
        XCTAssertEqual(distinct, ["senior", "staff", "mid"], "eight values must collapse to three")
    }

    /// #3 through the store, not just the pure function.
    func testUnusableValuesAreCleared() async throws {
        let (store, container) = try store()
        try seed(container, ["5+ years", "III", "Senior"])

        let result = try await store.normalizeStoredSeniority()
        XCTAssertEqual(result.cleared, 2)
        XCTAssertEqual(try Set(stored(container).compactMap(\.self)), ["senior"])
    }

    /// #4: a second run must be a no-op, or the migrator can't be re-run safely.
    func testBackfillIsIdempotent() async throws {
        let (store, container) = try store()
        try seed(container, ["Senior", "mid_senior", "5+ years"])

        let first = try await store.normalizeStoredSeniority()
        XCTAssertGreaterThan(first.changed, 0)

        let second = try await store.normalizeStoredSeniority()
        XCTAssertEqual(second.changed, 0, "re-running must change nothing")
    }

    func testAlreadyCanonicalRowsAreUntouched() async throws {
        let (store, container) = try store()
        try seed(container, ["senior", "staff", nil])

        let result = try await store.normalizeStoredSeniority()
        XCTAssertEqual(result.changed, 0)
    }
}

/// Rule ORDER decides the band, because the first matching needle wins. A compound title whose
/// modifier also appears as a standalone rule was therefore decided by the modifier: "Associate
/// Director" normalized to `entry`, which is what then reached `experience_level` in the scoring
/// prompt.
final class SeniorityCompoundTitleTests: XCTestCase {
    func testAssociateCompoundsKeepTheirOwnBand() {
        XCTAssertEqual(SeniorityNormalizer.normalize("Associate Director"), "director")
        XCTAssertEqual(SeniorityNormalizer.normalize("associate manager"), "manager")
        XCTAssertEqual(SeniorityNormalizer.normalize("Associate Vice President"), "executive")
        // The bare word still means what it meant.
        XCTAssertEqual(SeniorityNormalizer.normalize("Associate"), "entry")
        XCTAssertEqual(SeniorityNormalizer.normalize("Associate Engineer"), "entry")
    }

    func testSeniorCompoundsDoNotCollapseToSenior() {
        XCTAssertEqual(SeniorityNormalizer.normalize("Senior Staff Engineer"), "staff")
        XCTAssertEqual(SeniorityNormalizer.normalize("Sr. Principal Engineer"), "principal")
        XCTAssertEqual(SeniorityNormalizer.normalize("Senior Manager"), "manager")
        XCTAssertEqual(SeniorityNormalizer.normalize("Senior Director"), "director")
        XCTAssertEqual(SeniorityNormalizer.normalize("Senior Engineer"), "senior")
    }
}
