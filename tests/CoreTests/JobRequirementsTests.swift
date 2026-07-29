import XCTest
@testable import JobhuntCore

/// The criteria verdict used to mean location only, so a remote US role paying well under the user's
/// floor still read as "meets" — useless for triaging an Interested list before applying.
final class JobRequirementsTests: XCTestCase {
    private func evaluate(
        meets: Bool? = true,
        remote: RemoteType? = .remote,
        salaryMin: Int? = nil,
        salaryMax: Int? = nil,
        currency: String? = "USD",
        fit: Int? = nil,
        minSalary: Int = 0,
        minFit: Int = 0
    ) -> JobRequirements.Verdict? {
        JobRequirements.evaluate(
            meetsCriteria: meets, remoteType: remote, salaryMin: salaryMin, salaryMax: salaryMax,
            salaryCurrency: currency, fitScore: fit,
            thresholds: JobRequirements.Thresholds(minSalary: minSalary, minFitScore: minFit)
        )
    }

    // MARK: - Off by default

    /// An install that has configured no floors must behave exactly as before.
    func testUnconfiguredThresholdsChangeNothing() {
        XCTAssertEqual(evaluate(salaryMax: 50000, fit: 3)?.bucket, .meets)
    }

    // MARK: - Salary

    func testSalaryCeilingBelowFloorFails() {
        let verdict = evaluate(salaryMin: 120_000, salaryMax: 180_000, minSalary: 200_000)
        XCTAssertEqual(verdict?.bucket, .doesNotMeet)
        XCTAssertEqual(verdict?.failures.first, "Pays up to $180k, below your $200k floor")
    }

    /// Judged on the TOP of the range — a band straddling the floor still qualifies.
    func testRangeStraddlingTheFloorQualifies() {
        XCTAssertEqual(evaluate(salaryMin: 160_000, salaryMax: 240_000, minSalary: 200_000)?.bucket, .meets)
    }

    func testExactlyAtTheFloorQualifies() {
        XCTAssertEqual(evaluate(salaryMax: 200_000, minSalary: 200_000)?.bucket, .meets)
    }

    /// With no maximum recorded, the single figure is what there is to judge.
    func testFallsBackToMinimumWhenNoMaximum() {
        XCTAssertEqual(evaluate(salaryMin: 150_000, minSalary: 200_000)?.bucket, .doesNotMeet)
        XCTAssertEqual(evaluate(salaryMin: 250_000, minSalary: 200_000)?.bucket, .meets)
    }

    /// The user's explicit choice: a posting that publishes no band is unknown, not disqualified.
    func testMissingSalaryIsNotStatedRatherThanFailing() {
        let verdict = evaluate(minSalary: 200_000)
        XCTAssertEqual(verdict?.bucket, .notStated)
        XCTAssertEqual(verdict?.unstated, ["No salary stated"])
        XCTAssertTrue(verdict?.failures.isEmpty ?? false)
    }

    func testZeroSalaryIsTreatedAsMissing() {
        XCTAssertEqual(evaluate(salaryMin: 0, salaryMax: 0, minSalary: 200_000)?.bucket, .notStated)
    }

    /// Converting at an invented rate would be worse than admitting we can't compare.
    func testForeignCurrencyIsNotComparedAgainstAUSDFloor() {
        let verdict = evaluate(salaryMax: 100_000, currency: "EUR", minSalary: 200_000)
        XCTAssertEqual(verdict?.bucket, .notStated)
        XCTAssertEqual(verdict?.unstated.first, "Salary in EUR — not comparable")
    }

    func testAbsentCurrencyIsAssumedUSD() {
        XCTAssertEqual(evaluate(salaryMax: 180_000, currency: nil, minSalary: 200_000)?.bucket, .doesNotMeet)
    }

    // MARK: - Fit

    func testFitBelowFloorFails() {
        let verdict = evaluate(fit: 42, minFit: 50)
        XCTAssertEqual(verdict?.bucket, .doesNotMeet)
        XCTAssertEqual(verdict?.failures.first, "Fit 42, below your minimum of 50")
    }

    func testFitAtFloorQualifies() {
        XCTAssertEqual(evaluate(fit: 50, minFit: 50)?.bucket, .meets)
    }

    func testUnscoredJobIsNotStatedRatherThanFailing() {
        let verdict = evaluate(minFit: 50)
        XCTAssertEqual(verdict?.bucket, .notStated)
        XCTAssertEqual(verdict?.unstated, ["Not scored yet"])
    }

    // MARK: - Combining

    /// A definite miss outranks a gap in the data — one requirement it demonstrably fails is enough.
    func testAFailureOutranksAnUnknown() {
        let verdict = evaluate(salaryMax: 100_000, fit: nil, minSalary: 200_000, minFit: 50)
        XCTAssertEqual(verdict?.bucket, .doesNotMeet)
        XCTAssertEqual(verdict?.failures.count, 1)
        XCTAssertEqual(verdict?.unstated, ["Not scored yet"])
    }

    func testEveryFailedRequirementIsReported() {
        let verdict = evaluate(
            meets: false, remote: .remote, salaryMax: 100_000, fit: 10, minSalary: 200_000, minFit: 50
        )
        XCTAssertEqual(verdict?.failures.count, 3, verdict?.summary ?? "")
        XCTAssertTrue(verdict?.summary.contains("Location") ?? false)
        XCTAssertTrue(verdict?.summary.contains("$200k") ?? false)
        XCTAssertTrue(verdict?.summary.contains("Fit 10") ?? false)
    }

    func testLocationFailureStillCountsOnItsOwn() {
        XCTAssertEqual(evaluate(meets: false, remote: .remote)?.bucket, .doesNotMeet)
    }

    /// An unstated arrangement stays a "look at this", not a rejection.
    func testUnstatedArrangementIsNotAFailure() {
        let verdict = evaluate(meets: false, remote: nil)
        XCTAssertEqual(verdict?.bucket, .notStated)
        XCTAssertEqual(verdict?.unstated, ["Work arrangement not stated"])
    }

    /// Contract preserved from `criteriaBucket`: a job whose verdict was never computed matches no
    /// bucket rather than being lumped in with the rejects.
    func testUncomputedVerdictReturnsNil() {
        XCTAssertNil(evaluate(meets: nil))
    }

    func testMeetingEverythingSaysSo() {
        let verdict = evaluate(salaryMax: 250_000, fit: 80, minSalary: 200_000, minFit: 50)
        XCTAssertEqual(verdict?.bucket, .meets)
        XCTAssertEqual(verdict?.summary, "Meets your requirements")
    }
}
