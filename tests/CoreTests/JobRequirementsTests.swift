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
        XCTAssertEqual(verdict?.failures.first?.long, "Pays up to $180k, below your $200k floor")
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
        XCTAssertEqual(verdict?.unstated.map(\.long), ["No salary stated"])
        XCTAssertTrue(verdict?.failures.isEmpty ?? false)
    }

    func testZeroSalaryIsTreatedAsMissing() {
        XCTAssertEqual(evaluate(salaryMin: 0, salaryMax: 0, minSalary: 200_000)?.bucket, .notStated)
    }

    /// Converting at an invented rate would be worse than admitting we can't compare.
    func testForeignCurrencyIsNotComparedAgainstAUSDFloor() {
        let verdict = evaluate(salaryMax: 100_000, currency: "EUR", minSalary: 200_000)
        XCTAssertEqual(verdict?.bucket, .notStated)
        XCTAssertEqual(verdict?.unstated.first?.long, "Salary in EUR — not comparable")
    }

    func testAbsentCurrencyIsAssumedUSD() {
        XCTAssertEqual(evaluate(salaryMax: 180_000, currency: nil, minSalary: 200_000)?.bucket, .doesNotMeet)
    }

    // MARK: - Fit

    func testFitBelowFloorFails() {
        let verdict = evaluate(fit: 42, minFit: 50)
        XCTAssertEqual(verdict?.bucket, .doesNotMeet)
        XCTAssertEqual(verdict?.failures.first?.long, "Fit 42, below your minimum of 50")
    }

    func testFitAtFloorQualifies() {
        XCTAssertEqual(evaluate(fit: 50, minFit: 50)?.bucket, .meets)
    }

    func testUnscoredJobIsNotStatedRatherThanFailing() {
        let verdict = evaluate(minFit: 50)
        XCTAssertEqual(verdict?.bucket, .notStated)
        XCTAssertEqual(verdict?.unstated.map(\.long), ["Not scored yet"])
    }

    // MARK: - Combining

    /// A definite miss outranks a gap in the data — one requirement it demonstrably fails is enough.
    func testAFailureOutranksAnUnknown() {
        let verdict = evaluate(salaryMax: 100_000, fit: nil, minSalary: 200_000, minFit: 50)
        XCTAssertEqual(verdict?.bucket, .doesNotMeet)
        XCTAssertEqual(verdict?.failures.count, 1)
        XCTAssertEqual(verdict?.unstated.map(\.long), ["Not scored yet"])
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
        XCTAssertEqual(verdict?.unstated.map(\.long), ["Work arrangement not stated"])
    }

    /// Contract preserved from `criteriaBucket`: a job whose verdict was never computed matches no
    /// bucket rather than being lumped in with the rejects.
    func testUncomputedVerdictReturnsNil() {
        XCTAssertNil(evaluate(meets: nil))
    }

    // MARK: - Badge text (the reason must be readable without hovering)

    /// The reported case: job #612 read as "Outside criteria" with nothing indicating that its fit of
    /// 44 against a floor of 50 was the sole cause.
    func testBadgeNamesTheFailingRequirementInline() {
        let verdict = evaluate(salaryMax: 267_900, fit: 44, minSalary: 200_000, minFit: 50)
        XCTAssertEqual(verdict?.bucket, .doesNotMeet)
        XCTAssertEqual(verdict?.badgeText("Outside criteria"), "Fit 44, under your minimum of 50")
        XCTAssertEqual(verdict?.summary, "Fit 44, below your minimum of 50")
    }

    /// "Arrangement not stated: arrangement not stated" — the label was being prefixed onto a reason
    /// that already said the same thing.
    func testBadgeDoesNotRepeatTheBucketLabel() {
        let verdict = evaluate(meets: false, remote: nil)
        let text = verdict?.badgeText("Not stated") ?? ""
        XCTAssertEqual(text, "Work arrangement not stated")
        XCTAssertFalse(text.contains(":"), "the label must not be prefixed onto the reason: \(text)")
    }

    func testBadgeIsUnadornedWhenEverythingPasses() {
        let verdict = evaluate(salaryMax: 250_000, fit: 80, minSalary: 200_000, minFit: 50)
        XCTAssertEqual(verdict?.badgeText("Meets criteria"), "Meets criteria")
        XCTAssertNil(verdict?.shortSummary)
    }

    func testBadgeShowsTheGapWhenNothingFailed() {
        let verdict = evaluate(minSalary: 200_000)
        XCTAssertEqual(verdict?.badgeText("Not stated"), "No salary stated")
    }

    /// With several misses the badge lists them rather than picking one arbitrarily.
    func testBadgeListsEveryFailure() {
        let verdict = evaluate(salaryMax: 100_000, fit: 10, minSalary: 200_000, minFit: 50)
        XCTAssertEqual(
            verdict?.badgeText("Outside criteria"),
            "Pays ≤ $100k, under your $200k floor, Fit 10, under your minimum of 50"
        )
    }

    /// Failures decide the bucket, so the badge must not dilute them with unrelated gaps.
    func testBadgeOmitsUnknownsWhenSomethingDefinitelyFailed() {
        let verdict = evaluate(fit: 10, minSalary: 200_000, minFit: 50)
        XCTAssertEqual(verdict?.badgeText("Outside criteria"), "Fit 10, under your minimum of 50")
    }

    func testMeetingEverythingSaysSo() {
        let verdict = evaluate(salaryMax: 250_000, fit: 80, minSalary: 200_000, minFit: 50)
        XCTAssertEqual(verdict?.bucket, .meets)
        XCTAssertEqual(verdict?.summary, "Meets your requirements")
    }
}
