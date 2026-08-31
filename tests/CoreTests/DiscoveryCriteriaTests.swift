import Foundation
import XCTest
@testable import JobhuntCore

/// Gate A — what a swept posting must clear before jobhunt spends anything on it (TASK-691, M2).
///
/// Every test here names the failure it prevents. The rules are ports from the career-ops scanner,
/// and each one exists because the obvious implementation silently lost real postings: a filter
/// that rejects too much reports the same "0 new" as a filter that's working, so nothing on screen
/// distinguishes them. That asymmetry is why the tests lean on the reject side.
final class DiscoveryCriteriaTests: XCTestCase {
    private func posting(
        title: String = "Senior Program Manager",
        location: String? = "Remote, United States",
        published: Date? = nil,
        salaryMin: Int? = nil,
        salaryMax: Int? = nil
    ) -> DiscoveredPosting {
        DiscoveredPosting(
            dedupKey: "gh:1", url: "https://boards.greenhouse.io/acme/jobs/1", title: title,
            company: "Acme", locationRaw: location, firstPublished: published,
            salaryMinPublished: salaryMin, salaryMaxPublished: salaryMax
        )
    }

    // MARK: - Absent data never rejects

    /// The single most important rule. Gate A must never be stricter than the post-extraction
    /// requirement check, or it permanently hides roles the user's own settings would have
    /// accepted — and hides them where no screen will ever show them.
    func testAbsentDataAlwaysPasses() {
        let criteria = DiscoveryCriteria(
            locationAllow: ["united states"], minSalaryIfPublished: 200_000, maxAgeDays: 7
        )
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Program Manager", location: nil)), .pass,
            "no location is unknown, not disqualifying"
        )
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Program Manager", location: "United States", salaryMin: nil)),
            .pass, "no published band is unknown, not 'doesn't pay enough'"
        )
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Program Manager", location: "United States", published: nil)),
            .pass, "no date is unknown, not stale"
        )
    }

    // MARK: - Title

    func testTitleNeedsOneOfTheIncludeKeywords() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["program manager", "product manager"])
        XCTAssertEqual(criteria.evaluate(posting(title: "Senior Program Manager, Platform")), .pass)
        XCTAssertEqual(criteria.evaluate(posting(title: "Staff Backend Engineer")), .reject(.title))
    }

    func testAnExcludeKeywordVetoesEvenAMatchingTitle() {
        let criteria = DiscoveryCriteria(
            titleIncludeAny: ["program manager"], titleExcludeAny: ["intern", "junior"]
        )
        XCTAssertEqual(criteria.evaluate(posting(title: "Junior Program Manager")), .reject(.title))
    }

    func testNoIncludeKeywordsMeansEveryTitlePasses() {
        XCTAssertEqual(DiscoveryCriteria().evaluate(posting(title: "Anything At All")), .pass)
    }

    /// A 2–3 letter keyword is anchored on word boundaries. Without this, "COO" matches
    /// *Coordinator* and "AI" matches *Maintenance* — and the sweep summary reports one "passed"
    /// count that can't tell a tuned filter from a leaking one.
    func testShortKeywordsDoNotMatchInsideLongerWords() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["coo"])
        XCTAssertEqual(criteria.evaluate(posting(title: "Program Coordinator")), .reject(.title))
        XCTAssertEqual(criteria.evaluate(posting(title: "COO, Operations")), .pass)

        let tpm = DiscoveryCriteria(titleIncludeAny: ["tpm"])
        XCTAssertEqual(tpm.evaluate(posting(title: "Senior TPM, Infrastructure")), .pass)
    }

    /// Longer keywords stay permissive on purpose — anchoring them would break the ordinary case
    /// of a keyword appearing inside a longer real title.
    func testLongerKeywordsStayPermissive() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["program manager"])
        XCTAssertEqual(criteria.evaluate(posting(title: "Senior Program Manager (Remote)")), .pass)
    }

    /// An empty keyword would match everything via `contains("")`, silently disabling its tier —
    /// so a stray blank entry in a token field would turn a block list into a no-op.
    func testAnEmptyKeywordDoesNotMatchEverything() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["   "], titleExcludeAny: [""])
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Staff Backend Engineer")), .reject(.title),
            "a blank include must not admit every posting"
        )
    }

    // MARK: - Location

    /// The motivating bug, kept as a test because it is invisible in production: blocking "india"
    /// also rejected Indian Head MD, Indiana and Indianapolis — real US locations, dropped from
    /// every scan.
    func testLocationKeywordsNeverMatchInsideAnotherPlaceName() {
        let criteria = DiscoveryCriteria(locationBlock: ["india"])
        XCTAssertEqual(criteria.evaluate(posting(location: "Indianapolis, IN")), .pass)
        XCTAssertEqual(criteria.evaluate(posting(location: "Indian Head, MD")), .pass)
        XCTAssertEqual(criteria.evaluate(posting(location: "Bengaluru, India")), .reject(.location))
    }

    func testAllowListRequiresAMatchWhenNonEmpty() {
        let criteria = DiscoveryCriteria(locationAllow: ["united states"])
        XCTAssertEqual(criteria.evaluate(posting(location: "Austin, United States")), .pass)
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Program Manager", location: "Berlin, Germany")),
            .reject(.location)
        )
    }

    /// A multi-location posting is available somewhere the user wants, so one blocked city in the
    /// list must not kill it.
    func testAlwaysAllowBeatsBlockOnAMultiLocationPosting() {
        let criteria = DiscoveryCriteria(
            locationAlwaysAllow: ["stockholm"], locationBlock: ["london"]
        )
        XCTAssertEqual(criteria.evaluate(posting(location: "Stockholm · London · Madrid")), .pass)
    }

    /// …but that unconditional win then discards a legitimate country-level block, because a
    /// European city name can be a whole word inside a non-European location. `blockHard` is the
    /// one tier `alwaysAllow` cannot override.
    func testBlockHardIsTheOneTierAlwaysAllowCannotOverride() {
        let criteria = DiscoveryCriteria(
            locationBlockHard: ["brazil"], locationAlwaysAllow: ["porto"]
        )
        XCTAssertEqual(
            criteria.evaluate(posting(location: "Porto Alegre, Rio Grande do Sul, Brazil")),
            .reject(.location)
        )
        XCTAssertEqual(
            criteria.evaluate(posting(location: "Porto, Portugal")), .pass,
            "the always-allow entry still works where no hard block applies"
        )
    }

    // MARK: - Remote title rescue

    /// Several ATSs report the hiring office as the location even when the role is remote, and say
    /// so only in the title. One measured tenant: 14 matching postings, 0 passed `allow`, 5 said
    /// Remote outright in the title.
    func testARemoteTitleRescuesAnAllowMiss() {
        let criteria = DiscoveryCriteria(locationAllow: ["united states"])
        XCTAssertEqual(criteria.evaluate(
            posting(title: "Program Manager - Remote", location: "Las Vegas, Nevada")
        ), .pass)
    }

    /// The rescue widens `allow`, never `block`. A remote-titled role in a blocked location stays
    /// rejected — otherwise the block list would be silently unenforceable.
    func testARemoteTitleCannotRescueABlockedLocation() {
        let criteria = DiscoveryCriteria(locationBlock: ["india"], locationAllow: ["united states"])
        XCTAssertEqual(criteria.evaluate(
            posting(title: "Program Manager - Remote", location: "Bengaluru, India")
        ), .reject(.location))
    }

    /// A bare search for the word admits domain compounds: "Remote Sensing Program Manager" is an
    /// on-site GIS role, and companies post exactly those.
    func testRemoteSensingIsNotARemoteRole() {
        let criteria = DiscoveryCriteria(locationAllow: ["united states"])
        XCTAssertEqual(criteria.evaluate(
            posting(title: "Remote Sensing Program Manager", location: "Redlands, California")
        ), .reject(.location))
    }

    /// In "Non-Remote" the delimiter clears the lookbehind and the trailing position clears the
    /// lookahead, so an explicitly on-site role would otherwise bypass a non-empty allow list —
    /// the exact opposite of the intent. Non-ASCII dashes included, since an ASCII-only separator
    /// lets every one of them through.
    func testANegatedRemoteTitleDoesNotRescue() {
        let criteria = DiscoveryCriteria(locationAllow: ["united states"])
        for title in [
            "Program Manager - Non-Remote",
            "Program Manager (Not Remote)",
            "Program Manager – Non–Remote"
        ] {
            XCTAssertEqual(
                criteria.evaluate(posting(title: title, location: "Berlin, Germany")),
                .reject(.location), title
            )
        }
    }

    /// The negation must never cross a letter, or ordinary titles starting with "non" would lose
    /// their rescue.
    func testTheNegationDoesNotReachAcrossAWord() {
        XCTAssertTrue(
            DiscoveryCriteria.titleSignalsRemote("Nonprofit Program Manager - Remote"),
            "the run after 'non' starts with 'profit', so the negation cannot reach the marker"
        )
    }

    // MARK: - Salary

    /// Overlap, not a floor: a band that straddles the user's minimum is a negotiation, not a
    /// mismatch.
    func testSalaryRejectsOnlyABandEntirelyOutsideTheRange() {
        let criteria = DiscoveryCriteria(minSalaryIfPublished: 150_000)
        XCTAssertEqual(criteria.evaluate(posting(salaryMin: 120_000, salaryMax: 180_000)), .pass)
        XCTAssertEqual(
            criteria.evaluate(posting(salaryMin: 80000, salaryMax: 100_000)), .reject(.salary)
        )
    }

    func testAMaximumRejectsOnlyABandEntirelyAboveIt() {
        let criteria = DiscoveryCriteria(maxSalaryIfPublished: 200_000)
        XCTAssertEqual(criteria.evaluate(posting(salaryMin: 180_000, salaryMax: 250_000)), .pass)
        XCTAssertEqual(
            criteria.evaluate(posting(salaryMin: 300_000, salaryMax: 400_000)), .reject(.salary)
        )
    }

    /// A one-sided band is still usable — treat the single figure as both ends rather than
    /// discarding the signal.
    func testAOneSidedBandIsStillEvaluated() {
        let criteria = DiscoveryCriteria(minSalaryIfPublished: 150_000)
        XCTAssertEqual(criteria.evaluate(posting(salaryMin: 90000, salaryMax: nil)), .reject(.salary))
        XCTAssertEqual(criteria.evaluate(posting(salaryMin: nil, salaryMax: 190_000)), .pass)
    }

    // MARK: - Age

    func testAgeRejectsOnlyDatedPostingsPastTheWindow() {
        let now = Date()
        let criteria = DiscoveryCriteria(maxAgeDays: 14)
        XCTAssertEqual(
            criteria.evaluate(posting(published: now.addingTimeInterval(-3 * 86400)), now: now), .pass
        )
        XCTAssertEqual(
            criteria.evaluate(posting(published: now.addingTimeInterval(-30 * 86400)), now: now),
            .reject(.stale)
        )
    }

    /// Workday's "Posted 30+ Days Ago" bucket yields no date at all, so an age filter that rejected
    /// undated postings would silently discard most of a Workday tenant.
    func testAnUndatedPostingIsNeverStale() {
        let criteria = DiscoveryCriteria(maxAgeDays: 1)
        XCTAssertEqual(criteria.evaluate(posting(published: nil)), .pass)
    }

    func testAgeZeroDisablesTheWindow() {
        let now = Date()
        let criteria = DiscoveryCriteria(maxAgeDays: 0)
        XCTAssertEqual(
            criteria.evaluate(posting(published: now.addingTimeInterval(-900 * 86400)), now: now),
            .pass
        )
    }

    // MARK: - Ordering and identity

    /// The histogram is only useful if a posting is attributed to the first thing it failed, and
    /// title is checked first because it rejects 96% of everything — reporting those as location
    /// failures would send the user to tune the wrong list.
    func testTitleIsAttributedBeforeLocation() {
        let criteria = DiscoveryCriteria(
            titleIncludeAny: ["program manager"], locationAllow: ["united states"]
        )
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Backend Engineer", location: "Berlin, Germany")),
            .reject(.title)
        )
    }

    /// The ledger stores this hash beside each verdict so a criteria change re-evaluates the
    /// postings it already judged. If the hash didn't move, a widened filter would never see the
    /// thousands of rows it previously rejected.
    func testChangingAnyFieldChangesTheHash() {
        let base = DiscoveryCriteria(titleIncludeAny: ["program manager"])
        var widened = base
        widened.titleIncludeAny.append("product manager")
        XCTAssertNotEqual(base.hashValue, widened.hashValue)
        XCTAssertNotEqual(base, widened)
    }

    // MARK: - Dedup key

    func testTheDedupKeyPrefersTheATSIdentity() {
        XCTAssertEqual(
            DiscoveredPosting.dedupKey(for: "https://boards.greenhouse.io/acme/jobs/4567"),
            "gh:4567"
        )
    }

    /// Aggregators and company career pages have no ATS id, and they still need a key — otherwise
    /// every sweep re-ingests them.
    func testANonATSURLFallsBackToANormalisedURL() throws {
        let key = try XCTUnwrap(
            DiscoveredPosting.dedupKey(for: "https://Careers.Example.com/jobs/42?utm_source=x#top")
        )
        XCTAssertEqual(key, "url:https://careers.example.com/jobs/42")
        XCTAssertNil(DiscoveredPosting.dedupKey(for: "not a url"))
    }

    /// The prefix keeps the namespaces apart: an ATS id and a URL that spelled the same characters
    /// must not collide in the ledger.
    func testTheTwoKeyNamespacesCannotCollide() throws {
        let urlKey = try XCTUnwrap(DiscoveredPosting.dedupKey(for: "https://example.com/gh:4567"))
        XCTAssertTrue(urlKey.hasPrefix("url:"))
        XCTAssertNotEqual(urlKey, "gh:4567")
    }
}

/// The URL as a second statement of location (found by comparing against career-ops' real output).
final class DiscoveryLocationHintTests: XCTestCase {
    private func posting(title: String = "Program Manager", location: String?, url: String) -> DiscoveredPosting {
        DiscoveredPosting(
            dedupKey: "x", url: url, title: title, company: "Acme", locationRaw: location
        )
    }

    /// The case that motivated this: a tenant reporting a city while its own URL says the role is
    /// remote. Checking only the display string drops it, silently.
    func testTheURLCanSupplyALocationTheDisplayStringOmits() {
        let criteria = DiscoveryCriteria(locationAllow: ["remote"])
        XCTAssertEqual(criteria.evaluate(posting(
            location: "Indianapolis, IN",
            url: "https://acme.wd1.myworkdayjobs.com/careers/job/US-TX-Remote/Program-Manager_R-1"
        )), .pass)
    }

    /// A rollup count names no place, so the URL is the only thing left to judge on.
    func testARollupFallsBackToTheURL() {
        let criteria = DiscoveryCriteria(locationAllow: ["remote"])
        XCTAssertEqual(criteria.evaluate(posting(
            location: "46 Locations",
            url: "https://acme.wd1.myworkdayjobs.com/careers/job/Remote---Texas/Program-Manager_R-1"
        )), .pass)
    }

    /// The hint widens matching in *both* directions — a blocked country in the URL still blocks,
    /// or a block list could be bypassed by a tenant that displays a friendly location.
    func testTheURLCanAlsoTriggerABlock() {
        let criteria = DiscoveryCriteria(locationBlock: ["india"], locationAllow: ["remote"])
        XCTAssertEqual(criteria.evaluate(posting(
            location: "Remote",
            url: "https://acme.wd1.myworkdayjobs.com/careers/job/Hyderabad-India/Program-Manager_R-1"
        )), .reject(.location))
    }

    /// Only the segment after `/job/` is read. A tenant whose *hostname* contains a blocked word
    /// must not be rejected for it.
    func testOnlyTheJobSegmentIsRead() {
        let criteria = DiscoveryCriteria(locationBlock: ["india"], locationAllow: ["remote"])
        XCTAssertEqual(criteria.evaluate(posting(
            location: "Remote, United States",
            url: "https://indiamart.wd1.myworkdayjobs.com/india-careers/job/Austin-TX/PM_R-1"
        )), .pass)
    }

    /// Nothing to judge on either field still passes — absent data never rejects.
    func testNoLocationAnywhereStillPasses() {
        let criteria = DiscoveryCriteria(locationAllow: ["remote"])
        XCTAssertEqual(
            criteria.evaluate(posting(location: nil, url: "https://example.com/jobs/1")), .pass
        )
    }
}

/// Gate rules a user's own settings can reach that the ported career-ops config never did
/// (TASK-703 follow-up).
final class DiscoveryGateEdgeCaseTests: XCTestCase {
    private func posting(title: String = "Senior Program Manager") -> DiscoveredPosting {
        DiscoveredPosting(
            dedupKey: "gh:1", url: "https://boards.greenhouse.io/acme/jobs/1", title: title,
            company: "Acme", locationRaw: "Remote, United States"
        )
    }

    // MARK: - Short keywords are anchored

    /// Unanchored, a one-character include keyword matches every title through `contains` — which
    /// silently disables the title filter and lets a sweep spend the whole daily cap on arbitrary
    /// jobs. That is the outcome the interlock exists to prevent, reached through a field the user
    /// filled in.
    func testAOneCharacterIncludeKeywordDoesNotMatchEverything() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["c"])
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Senior Program Manager")),
            .reject(.title)
        )
        XCTAssertEqual(criteria.evaluate(posting(title: "Engineer, C")), .pass)
    }

    /// And unanchored, a one-character exclude keyword rejects nearly every posting there is.
    func testAOneCharacterExcludeKeywordDoesNotRejectEverything() {
        let criteria = DiscoveryCriteria(
            titleIncludeAny: ["program manager"], titleExcludeAny: ["r"]
        )
        XCTAssertEqual(criteria.evaluate(posting(title: "Senior Program Manager")), .pass)
    }

    /// The existing two- and three-character behaviour is unchanged.
    func testTwoAndThreeCharacterKeywordsStillAnchor() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["tpm"])
        XCTAssertEqual(criteria.evaluate(posting(title: "TPM, Infrastructure")), .pass)
        XCTAssertEqual(criteria.evaluate(posting(title: "Contpmanager")), .reject(.title))
    }

    // MARK: - Fingerprint covers the logic, not just the settings

    /// The mechanism bug behind both fixes above: the fingerprint covered only the user's criteria
    /// values, so a posting rejected under a broken rule stayed marked as judged and the fix never
    /// reached it. `needsReevaluation` has to return true when the *rule* changes too.
    func testTheGateVersionParticipatesInTheFingerprint() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["program manager"])
        let entry = DiscoveryLedgerEntry(
            dedupKey: "gh:1", sourceID: "greenhouse", outcome: .rejected,
            rejectReason: .salary, criteriaFingerprint: "gate/v1-era-fingerprint"
        )
        XCTAssertTrue(
            entry.needsReevaluation(under: criteria.fingerprint),
            "a rejection recorded under older gate logic must be re-examined"
        )
    }

    /// …but an ingested posting stays terminal across a version bump, or bumping would resurrect
    /// jobs the user has since archived.
    func testAVersionBumpDoesNotResurrectIngestedPostings() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["program manager"])
        for outcome in [DiscoveryOutcome.ingested, .alreadyCaptured] {
            let entry = DiscoveryLedgerEntry(
                dedupKey: "gh:1", sourceID: "greenhouse", outcome: outcome,
                criteriaFingerprint: "gate/v1-era-fingerprint"
            )
            XCTAssertFalse(entry.needsReevaluation(under: criteria.fingerprint))
        }
    }
}

/// career-ops parity gaps the user's own ported config never exercised (TASK-703 follow-up).
///
/// Distinct from `DiscoveryCriteriaParityTests`, which checks the ported cases agree; these are
/// cases the port never covered because the config in hand never produced them.
final class DiscoveryCriteriaParityGapTests: XCTestCase {
    private func posting(
        title: String = "Senior Program Manager",
        location: String? = "Remote, United States",
        url: String = "https://boards.greenhouse.io/acme/jobs/1"
    ) -> DiscoveredPosting {
        DiscoveredPosting(
            dedupKey: "gh:1", url: url, title: title, company: "Acme", locationRaw: location
        )
    }

    // MARK: - `a + b` means both terms, any order

    /// Job titles interleave, so no single substring can express "a director role in engineering".
    /// Treated as a literal, the keyword matched nothing at all — a keyword that can never match is
    /// a silent false reject, which is the failure direction this gate exists to avoid.
    func testAPlusKeywordMatchesBothTermsInAnyOrder() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["director + engineering"])
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Senior Director, Platform Engineering")),
            .pass
        )
        XCTAssertEqual(criteria.evaluate(posting(title: "Engineering Director")), .pass)
    }

    func testAPlusKeywordStillNeedsEveryTerm() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["director + engineering"])
        XCTAssertEqual(criteria.evaluate(posting(title: "Director, Product")), .reject(.title))
        XCTAssertEqual(criteria.evaluate(posting(title: "Engineering Manager")), .reject(.title))
    }

    /// It works in the exclude list too, where it narrows rather than widens.
    func testAPlusKeywordInTheExcludeListNeedsEveryTerm() {
        let criteria = DiscoveryCriteria(
            titleIncludeAny: ["manager"], titleExcludeAny: ["junior + manager"]
        )
        XCTAssertEqual(
            criteria.evaluate(posting(title: "Junior Program Manager")),
            .reject(.title)
        )
        XCTAssertEqual(criteria.evaluate(posting(title: "Senior Program Manager")), .pass)
    }

    func testAStrayPlusIsNotAnEmptyTerm() {
        let criteria = DiscoveryCriteria(titleIncludeAny: ["manager +"])
        XCTAssertEqual(criteria.evaluate(posting(title: "Program Manager")), .pass)
        XCTAssertEqual(criteria.evaluate(posting(title: "Engineer")), .reject(.title))
    }

    // MARK: - Location normalisation

    /// Tenants emit all three separators interchangeably. Leaving two of them joined means a
    /// location keyword never boundary-matches on those postings — missed silently, on both the
    /// allow and block lists.
    func testUnderscoreAndPlusSeparatedURLLocationsAreRead() {
        for separator in ["-", "_", "+"] {
            let url = "https://acme.wd5.myworkdayjobs.com/en-US/careers/job/"
                + "United\(separator)States/Program-Manager_R1"
            let criteria = DiscoveryCriteria(
                titleIncludeAny: ["program manager"], locationBlock: ["united states"]
            )
            XCTAssertEqual(
                criteria.evaluate(posting(location: "4 Locations", url: url)),
                .reject(.location),
                "“United\(separator)States” has to read as a location"
            )
        }
    }

    /// A vendor sending a newline as its location is reporting nothing. Trimming only spaces left
    /// it looking like a location no keyword could match, which rejects rather than passing.
    func testAWhitespaceOnlyLocationCountsAsAbsent() {
        let criteria = DiscoveryCriteria(
            titleIncludeAny: ["program manager"], locationAllow: ["united states"]
        )
        XCTAssertEqual(
            criteria.evaluate(posting(location: "\n\t ", url: "https://x.test/j")),
            .pass
        )
    }

    // MARK: - Invalid salary configuration

    /// A floor above the ceiling rejects every band there is, invisibly. career-ops fails open.
    func testAnInvertedSalaryRangeFailsOpen() {
        let criteria = DiscoveryCriteria(
            titleIncludeAny: ["program manager"],
            minSalaryIfPublished: 300_000, maxSalaryIfPublished: 100_000
        )
        let band = DiscoveredPosting(
            dedupKey: "gh:1", url: "https://boards.greenhouse.io/acme/jobs/1",
            title: "Senior Program Manager", company: "Acme", locationRaw: "Remote, United States",
            salaryMinPublished: 150_000, salaryMaxPublished: 200_000
        )
        XCTAssertEqual(criteria.evaluate(band), .pass)
    }
}

/// Gate A's work-arrangement rule, and gate B's salary floor (TASK-702).
///
/// Both exist because the shipped gate could not act on two things the user had already told the
/// app. "Remote only" lived in the requirement settings and the gate never read it; the salary floor
/// lived in the gate but no board list endpoint publishes pay, so it never fired once — 493 postings
/// judged in a real install produced zero salary rejections.
final class DiscoveryArrangementAndPayTests: XCTestCase {
    private func posting(
        title: String = "Senior Program Manager", location: String?
    ) -> DiscoveredPosting {
        DiscoveredPosting(
            dedupKey: "gh:1", url: "https://boards.greenhouse.io/acme/jobs/1", title: title,
            company: "Acme", locationRaw: location
        )
    }

    private var remoteOnly: DiscoveryCriteria {
        DiscoveryCriteria(
            locationAllow: ["United States"],
            allowRemote: true, allowHybrid: false, allowOnsite: false
        )
    }

    // MARK: - Arrangement

    /// The reported bug, exactly. Every board writes the country into its location string, so a
    /// geography allow-list of "United States" matched an on-site Idaho posting — and it was swept,
    /// extracted, scored and filed for a user who accepts remote work only.
    func testOnsiteIsRejectedWhenOnlyRemoteIsAccepted() {
        XCTAssertEqual(
            remoteOnly.evaluate(posting(location: "Coeur d'Alene, Idaho, United States")),
            .reject(.arrangement)
        )
        XCTAssertEqual(
            remoteOnly.evaluate(posting(location: "Philadelphia, Pennsylvania, United States")),
            .reject(.arrangement)
        )
    }

    /// Prevention check for TASK-705: job #1424's exact shape — location "Lehi, Utah", no remote
    /// wording anywhere — must not reach ingest at all under remote-only criteria. #1424 predates
    /// this rule; a regression here would silently refill the pile the bucketing fix exists to
    /// surface.
    func testAJob1424ShapedPostingIsRejectedBeforeIngest() {
        let noGeographyFilter = DiscoveryCriteria(
            allowRemote: true, allowHybrid: false, allowOnsite: false
        )
        XCTAssertEqual(
            noGeographyFilter.evaluate(posting(title: "Staff Product Manager", location: "Lehi, Utah")),
            .reject(.arrangement)
        )
        // And with the user's geography allow-list in play it never even gets that far.
        XCTAssertEqual(
            remoteOnly.evaluate(posting(title: "Staff Product Manager", location: "Lehi, Utah")),
            .reject(.location)
        )
    }

    /// A posting that offers remote *as well as* an office is a remote posting. Rejecting it would
    /// throw away the exact roles the filter exists to find.
    func testARemoteOptionRescuesACityLocation() {
        XCTAssertEqual(
            remoteOnly.evaluate(posting(location: "Philadelphia, Pennsylvania, United States; Remote")),
            .pass
        )
        XCTAssertEqual(remoteOnly.evaluate(posting(location: "Remote, United States")), .pass)
        XCTAssertEqual(
            remoteOnly.evaluate(posting(title: "Program Manager (Remote)", location: "Austin, Texas")),
            .pass
        )
    }

    /// "Remote within Canada or United States" registered as *not remote* — the marker allowed
    /// "Remote in …" but not "Remote within …", and six rows in one install were lost to it.
    func testRemoteWithinAPlaceCountsAsRemote() {
        XCTAssertEqual(
            remoteOnly.evaluate(posting(
                location: "San Francisco, CA, or Remote within Canada or United States"
            )),
            .pass
        )
    }

    /// A country names no workplace, so it stays the absent-data case the rest of gate A is built
    /// around. This is the one on-site-shaped row that must still pass.
    func testACountryOnlyLocationIsNotAnOnsiteStatement() {
        XCTAssertEqual(remoteOnly.evaluate(posting(location: "United States")), .pass)
        XCTAssertEqual(remoteOnly.evaluate(posting(location: nil)), .pass)
    }

    /// The rule must be inert unless the user actually excluded something — an unconfigured install
    /// sweeps exactly as it did before.
    func testAcceptingOnsiteDisablesTheRuleEntirely() {
        let anything = DiscoveryCriteria(locationAllow: ["United States"])
        XCTAssertEqual(
            anything.evaluate(posting(location: "Coeur d'Alene, Idaho, United States")), .pass
        )
    }

    func testHybridIsAcceptedOnlyWhenItIsAllowed() {
        let posting = posting(location: "Austin, Texas, United States (Hybrid)")
        XCTAssertEqual(remoteOnly.evaluate(posting), .reject(.arrangement))
        var withHybrid = remoteOnly
        withHybrid.allowHybrid = true
        XCTAssertEqual(withHybrid.evaluate(posting), .pass)
    }

    /// Striking country words out to decide "does this name a place" must be anchored, or "us"
    /// erases the "us" in Austin and an on-site posting reads as country-level.
    func testStrikingCountryTermsDoesNotEatCityNames() {
        // "Austin" survives striking "us" out, so this still names a place and is rejected on
        // arrangement — not passed as country-level. The location tier has already accepted it, so a
        // reject here can only have come from the arrangement rule.
        XCTAssertEqual(
            remoteOnly.evaluate(posting(location: "Austin, Texas, United States")),
            .reject(.arrangement)
        )
    }

    // MARK: - Gate B

    func testTheSalaryFloorRejectsABandBelowIt() {
        let criteria = DiscoveryCriteria(minSalaryIfPublished: 180_000)
        XCTAssertEqual(
            criteria.evaluateHydrated(body: "The salary range is $100,000 - $125,000 USD."),
            .reject(.salary)
        )
    }

    func testTheSalaryFloorKeepsABandThatReachesIt() {
        let criteria = DiscoveryCriteria(minSalaryIfPublished: 180_000)
        XCTAssertEqual(
            criteria.evaluateHydrated(body: "Base pay: $150,000 - $210,000 per year."), .pass
        )
    }

    /// Unstated pay is unknown, not disqualifying — and the user still wants to see those.
    func testTextWithNoBandPasses() {
        let criteria = DiscoveryCriteria(minSalaryIfPublished: 180_000)
        XCTAssertEqual(criteria.evaluateHydrated(body: "We offer competitive pay."), .pass)
    }

    /// Several bands on one page are judged on the most generous, so a bonus quoted beside the
    /// salary can't become the salary.
    func testTheMostGenerousBandDecides() {
        let criteria = DiscoveryCriteria(minSalaryIfPublished: 180_000)
        XCTAssertEqual(
            criteria.evaluateHydrated(body: """
            Signing bonus: $5,000 - $10,000.
            Zone A base salary: $190,000 - $240,000.
            """),
            .pass
        )
    }

    /// `salaryBands` accepts anything over $1,000, which is right for parsing but far too weak to
    /// reject on: a real board produced `$2k–$2k` for a principal role, and treating that as the
    /// salary would discard a $250k posting permanently.
    func testAnImplausiblyLowBandCannotReject() {
        let criteria = DiscoveryCriteria(minSalaryIfPublished: 180_000)
        XCTAssertEqual(criteria.evaluateHydrated(body: "Equity: $2,000 - $2,000."), .pass)
    }

    func testNoFloorMeansNoGateB() {
        XCTAssertEqual(
            DiscoveryCriteria().evaluateHydrated(body: "$50,000 - $60,000 a year."), .pass
        )
    }

    /// Gate logic changed, so verdicts recorded under the old rules have to be re-judged. Without a
    /// bump, every posting already let through stays marked as judged and the fix reaches nothing.
    func testGateVersionWasBumped() {
        XCTAssertEqual(DiscoveryCriteria.gateVersion, 3)
    }
}
