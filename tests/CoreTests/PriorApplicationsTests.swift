import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-615: prior-application safeguard.
final class PriorApplicationsTests: XCTestCase {
    private func job(
        _ id: String, company: String?, title: String? = "Engineer", status: String = "pursuing",
        appliedAt: Date? = nil, number: Int? = nil
    ) -> PriorApplications.JobInput {
        .init(jobID: id, jobNumber: number, company: company, title: title, currentStatus: status, appliedAt: appliedAt)
    }

    func testNormalizedCompanyIgnoresLegalSuffixesAndPunctuation() {
        XCTAssertEqual(PriorApplications.normalizedCompany("Acme, Inc."), PriorApplications.normalizedCompany("Acme"))
        XCTAssertEqual(PriorApplications.normalizedCompany("Acme LLC"), "acme")
        XCTAssertEqual(PriorApplications.normalizedCompany("Inc."), "", "generic-only name normalizes to empty")
        XCTAssertNotEqual(PriorApplications.normalizedCompany("Acme"), PriorApplications.normalizedCompany("Acme Labs"))
    }

    func testFindsPriorApplicationAtSameCompanyRegardlessOfLaterStatus() {
        let viewed = job("v", company: "Acme, Inc.")
        let others = [
            job("a", company: "Acme", status: "rejected", appliedAt: Date()), // applied then rejected
            job("b", company: "Acme LLC", status: "interview"), // applied (implied), no date
            job("c", company: "Globex", status: "applied", appliedAt: Date()), // different company
            job("d", company: "Acme", status: "pursuing") // never applied → excluded
        ]
        let matches = PriorApplications.priorApplications(for: viewed, among: others)
        XCTAssertEqual(Set(matches.map(\.jobID)), ["a", "b"])
    }

    func testExcludesSelfAndEmptyCompany() {
        let viewed = job("v", company: "Acme", appliedAt: Date())
        XCTAssertTrue(PriorApplications.priorApplications(for: viewed, among: [viewed]).isEmpty, "self excluded")
        let noCompany = job("v", company: nil)
        XCTAssertTrue(
            PriorApplications.priorApplications(
                for: noCompany,
                among: [job("a", company: nil, status: "applied", appliedAt: Date())]
            ).isEmpty,
            "empty company never matches"
        )
    }

    func testLikelyRepeatWhenTitlesMatch() {
        let viewed = job("v", company: "Acme", title: "Staff Technical Program Manager")
        let others = [
            job(
                "same",
                company: "Acme",
                title: "Staff Technical Program Manager, Platform",
                status: "applied",
                appliedAt: Date()
            ),
            job("diff", company: "Acme", title: "Marketing Lead", status: "applied", appliedAt: Date())
        ]
        let matches = PriorApplications.priorApplications(for: viewed, among: others)
        XCTAssertEqual(matches.first { $0.jobID == "same" }?.likelyRepeat, true, "subset title → possible repeat")
        XCTAssertEqual(matches.first { $0.jobID == "diff" }?.likelyRepeat, false)
    }

    func testSortedNewestFirst() {
        let viewed = job("v", company: "Acme")
        let old = job("old", company: "Acme", status: "applied", appliedAt: Date(timeIntervalSince1970: 1000))
        let new = job("new", company: "Acme", status: "applied", appliedAt: Date(timeIntervalSince1970: 9000))
        XCTAssertEqual(PriorApplications.priorApplications(for: viewed, among: [old, new]).map(\.jobID), ["new", "old"])
    }
}
