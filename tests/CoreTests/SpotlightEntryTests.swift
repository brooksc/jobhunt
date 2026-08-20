import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// What a job looks like in the Spotlight index (TASK-590).
final class SpotlightEntryTests: XCTestCase {
    private func entry(
        jobNumber: Int? = 42,
        title: String? = "Staff TPM",
        company: String? = "Acme",
        location: String? = "Remote",
        salary: String? = "$180k–$220k",
        status: String = "Pursuing",
        skills: [String] = ["Kubernetes", "Terraform"]
    ) -> SpotlightEntry? {
        SpotlightEntry.make(
            jobNumber: jobNumber, title: title, company: company, location: location,
            salary: salary, status: status, skills: skills
        )
    }

    /// #1: the title is what Spotlight matches on first.
    func testTitleCombinesRoleAndCompany() throws {
        XCTAssertEqual(try XCTUnwrap(entry()).title, "Staff TPM at Acme")
    }

    /// #2: the deep link is the same `jobhunt://jobs/N` the notifications use, so a Spotlight hit
    /// lands in the same place as everything else.
    func testDeepLinkUsesTheJobNumber() throws {
        XCTAssertEqual(try XCTUnwrap(entry()).deepLink, "jobhunt://jobs/42")
    }

    /// The identifier has to be derivable from the job number alone, or a delete can't find the item
    /// it needs to remove.
    func testIdentifierIsDerivableFromTheNumber() throws {
        XCTAssertEqual(try XCTUnwrap(entry()).uniqueIdentifier, SpotlightEntry.identifier(jobNumber: 42))
    }

    /// A job with no number has no deep link, so a hit would open the app and land nowhere — worse
    /// than not appearing at all.
    func testUnnumberedJobIsNotIndexed() {
        XCTAssertNil(entry(jobNumber: nil))
    }

    /// Nothing to match on and nothing to show: a blank Spotlight row is worse than no row.
    func testJobWithNoTitleOrCompanyIsNotIndexed() {
        XCTAssertNil(entry(title: nil, company: nil))
        XCTAssertNil(entry(title: "  ", company: ""))
    }

    func testEitherTitleOrCompanyAloneIsEnough() throws {
        XCTAssertEqual(try XCTUnwrap(entry(company: nil)).title, "Staff TPM")
        XCTAssertEqual(try XCTUnwrap(entry(title: nil)).title, "Acme")
    }

    /// The company is a keyword as well as part of the title: someone searching "Acme" should hit
    /// every Acme job, whether or not its title reads well.
    func testCompanyIsAlsoAKeyword() throws {
        XCTAssertTrue(try XCTUnwrap(entry()).keywords.contains("Acme"))
        XCTAssertTrue(try XCTUnwrap(entry()).keywords.contains("Kubernetes"))
    }

    func testDescriptionCarriesLocationSalaryAndStatus() throws {
        let description = try XCTUnwrap(entry()).contentDescription
        XCTAssertTrue(description.contains("Remote"), description)
        XCTAssertTrue(description.contains("$180k"), description)
        XCTAssertTrue(description.contains("Pursuing"), description)
    }

    /// Missing fields are omitted rather than rendered as empty separators.
    func testMissingFieldsDontLeaveDanglingSeparators() throws {
        let description = try XCTUnwrap(entry(location: nil, salary: nil)).contentDescription
        XCTAssertEqual(description, "Pursuing")
    }
}

/// The indexing opt-out (TASK-590). Without it, "Clear Spotlight Index" only held until the next
/// launch republished everything, so a user who didn't want their job search in system-wide search
/// had no way to say so.
final class SpotlightIndexingSettingTests: XCTestCase {
    private func makeStore() throws -> SettingsStore {
        let container = try ModelContainerFactory.inMemory()
        return SettingsStore(modelContext: ModelContext(container))
    }

    /// Defaults on, matching the behaviour from when indexing was unconditional.
    func testDefaultsOn() throws {
        XCTAssertTrue(try makeStore().spotlightIndexingEnabled)
    }

    func testRoundTrips() throws {
        let store = try makeStore()
        store.spotlightIndexingEnabled = false
        XCTAssertFalse(store.spotlightIndexingEnabled)
        store.spotlightIndexingEnabled = true
        XCTAssertTrue(store.spotlightIndexingEnabled)
    }
}
