import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-628: authoritative Applied history → unemployment-evidence report + CSV.
final class ApplicationHistoryTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        // swiftlint:disable:previous force_unwrapping
    }

    private func job(
        id: String, number: Int? = nil, status: String = "applied", appliedAt: Date? = nil,
        events: [Date] = [], company: String? = "Acme", title: String? = "Engineer",
        url: String = "https://x.com/1", notes: String? = nil,
        evidence: ApplicationHistory.JobInput.Evidence? = nil
    ) -> ApplicationHistory.JobInput {
        .init(
            jobID: id, jobNumber: number, company: company, title: title, sourceURL: url,
            currentStatus: status, notes: notes, appliedAt: appliedAt, appliedEventDates: events,
            evidence: evidence
        )
    }

    func testIncludesAppliedRegardlessOfCurrentStatus() {
        let applied = date(2026, 3, 10)
        let records = ApplicationHistory.build(jobs: [
            job(id: "a", status: "rejected", appliedAt: applied),
            job(id: "b", status: "archived", appliedAt: applied),
            job(id: "c", status: "pursuing"), // never applied → excluded
            job(id: "d", status: "new") // excluded
        ])
        XCTAssertEqual(Set(records.map(\.jobID)), ["a", "b"], "applied-then-later-status stays; never-applied excluded")
    }

    func testFirstAppliedTimestampPrefersAppliedAtThenEarliestEvent() {
        let appliedAt = date(2026, 3, 10)
        let early = date(2026, 3, 5)
        let late = date(2026, 3, 8)
        XCTAssertEqual(
            ApplicationHistory.build(jobs: [job(id: "a", appliedAt: appliedAt, events: [late, early])]).first?.appliedAt,
            appliedAt, "appliedAt is authoritative when present"
        )
        XCTAssertEqual(
            ApplicationHistory.build(jobs: [job(id: "b", appliedAt: nil, events: [late, early])]).first?.appliedAt,
            early, "falls back to the earliest applied event"
        )
    }

    func testLegacyImpliedAppliedHasMissingDate() throws {
        let records = ApplicationHistory.build(jobs: [job(id: "a", status: "interview", appliedAt: nil, events: [])])
        let record = try XCTUnwrap(records.first)
        XCTAssertNil(record.appliedAt)
        XCTAssertFalse(record.hasApplicationDate, "legacy applied with no timestamp is a missing-date row")
    }

    func testOneRowPerJobEvenWithMultipleAppliedEvents() {
        let records = ApplicationHistory.build(jobs: [
            job(id: "a", appliedAt: date(2026, 3, 10), events: [date(2026, 3, 1), date(2026, 3, 2)])
        ])
        XCTAssertEqual(records.count, 1, "idempotent: one job → one application-contact row")
    }

    func testClaimWeekEndingIsSaturdayOfSunSatWeek() {
        // 2026-03-10 is a Tuesday; its Sun–Sat week is Mar 8 (Sun) … Mar 14 (Sat).
        let tuesday = date(2026, 3, 10)
        let ending = ApplicationHistory.claimWeekEnding(for: tuesday, calendar: cal)
        let comps = cal.dateComponents([.month, .day, .weekday], from: ending)
        XCTAssertEqual(comps.weekday, 7, "week-ending is a Saturday")
        XCTAssertEqual(comps.day, 14)
        XCTAssertEqual(ApplicationHistory.claimWeekEnding(for: date(2026, 3, 8), calendar: cal), ending, "Sunday → same week's Saturday")
        XCTAssertEqual(
            ApplicationHistory.claimWeekEnding(for: date(2026, 3, 14, hour: 23), calendar: cal),
            cal.startOfDay(for: date(2026, 3, 14)), "Saturday → itself"
        )
    }

    func testClaimWeekEndingRespectsTimeZone() {
        // 06:30 UTC Sun Mar 8 is Sat Mar 7 22:30 in Los Angeles → different claim weeks.
        var utc = cal; utc.timeZone = TimeZone(identifier: "UTC")!
        var la = cal; la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let instant = utc.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 6, minute: 30))!
        XCTAssertEqual(utc.component(.day, from: ApplicationHistory.claimWeekEnding(for: instant, calendar: utc)), 14)
        XCTAssertEqual(la.component(.day, from: ApplicationHistory.claimWeekEnding(for: instant, calendar: la)), 7)
    }

    func testDeterministicOrderNewestFirstMissingLast() {
        let records = ApplicationHistory.build(jobs: [
            job(id: "old", number: 1, appliedAt: date(2026, 3, 1)),
            job(id: "new", number: 2, appliedAt: date(2026, 3, 20)),
            job(id: "missing", number: 3, status: "interview")
        ])
        XCTAssertEqual(records.map(\.jobID), ["new", "old", "missing"], "newest first, missing-date last")
    }

    func testFilterByDateRangeKeepsMissingDropsOutOfRange() {
        let records = ApplicationHistory.build(jobs: [
            job(id: "in", appliedAt: date(2026, 3, 10)),
            job(id: "before", appliedAt: date(2026, 2, 1)),
            job(id: "missing", status: "offer")
        ])
        let filtered = ApplicationHistory.filter(records, from: date(2026, 3, 1), to: date(2026, 3, 31), calendar: cal)
        XCTAssertEqual(Set(filtered.map(\.jobID)), ["in", "missing"])
    }

    func testCSVHasHeaderEscapesAndFormulaProtection() {
        let record = ApplicationRecord(
            jobID: "j1", jobNumber: 42, appliedAt: date(2026, 3, 10), company: "=CMD(),Acme",
            jobTitle: "Eng, Sr", sourceURL: "https://x.com/1", currentStatus: "rejected", notes: "called\nrecruiter"
        )
        let csv = ExportService.applicationHistoryCSV(records: [record], calendar: cal)
        XCTAssertTrue(csv.hasPrefix(ExportService.applicationHistoryColumns.joined(separator: ",")))
        XCTAssertTrue(csv.contains("\"'=CMD(),Acme\""), "formula-trigger company is single-quote-prefixed + quoted")
        XCTAssertTrue(csv.contains("\"Eng, Sr\""), "comma field quoted")
        XCTAssertTrue(csv.contains("\"called\nrecruiter\""), "newline field quoted")
        XCTAssertTrue(csv.contains("2026-03-10"), "application date")
        XCTAssertTrue(csv.contains("2026-03-14"), "claim week ending Saturday")
    }

    func testEvidenceCorrectionFillsMissingDateAndFlowsToRecord() throws {
        let corrected = date(2026, 4, 1)
        let evidence = ApplicationHistory.JobInput.Evidence(
            correctedAppliedAt: corrected, contactMethod: "online", contactType: "application",
            employerWebsiteOrEmail: "jobs@acme.com", applicationResult: "applied"
        )
        let records = ApplicationHistory.build(jobs: [job(id: "a", status: "interview", appliedAt: nil, evidence: evidence)])
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.appliedAt, corrected, "the user correction fills the missing application date")
        XCTAssertEqual(record.contactMethod, "online")
        XCTAssertEqual(record.employerWebsiteOrEmail, "jobs@acme.com")
        XCTAssertTrue(record.missingEvidenceFields.isEmpty, "date + method + type + website + result all present")
    }

    func testEvidenceCorrectionOverridesExistingAppliedAt() throws {
        let evidence = ApplicationHistory.JobInput.Evidence(correctedAppliedAt: date(2026, 5, 5))
        let records = ApplicationHistory.build(jobs: [job(id: "a", appliedAt: date(2026, 3, 1), evidence: evidence)])
        XCTAssertEqual(try XCTUnwrap(records.first).appliedAt, date(2026, 5, 5))
    }

    func testMissingEvidenceFieldsListsGaps() throws {
        let records = ApplicationHistory.build(jobs: [job(id: "a", appliedAt: date(2026, 3, 10))])
        let missing = try XCTUnwrap(records.first).missingEvidenceFields
        XCTAssertFalse(missing.contains("application date"), "date is present")
        XCTAssertTrue(missing.contains("contact method"))
        XCTAssertTrue(missing.contains("result"))
    }

    func testCSVMissingDateLeavesDateColumnsEmpty() {
        let record = ApplicationRecord(
            jobID: "j", jobNumber: nil, appliedAt: nil, company: "Acme", jobTitle: "E",
            sourceURL: "", currentStatus: "interview", notes: nil
        )
        let csv = ExportService.applicationHistoryCSV(records: [record], calendar: cal)
        let dataLine = String(csv.split(separator: "\n")[1])
        XCTAssertTrue(dataLine.hasPrefix(",,Job application,"), "empty application_date + claim_week, then activity_type")
    }
}
