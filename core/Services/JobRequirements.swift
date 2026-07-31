import Foundation

// MARK: - JobRequirements

/// Whether a job clears *all* of the user's configured requirements — location, salary floor, and fit
/// floor — and, when it doesn't, which ones it failed.
///
/// The criteria verdict used to mean location only, which made it a weak triage tool: a remote US role
/// paying half the user's floor still read as "meets". Salary and fit are evaluated here rather than
/// stored on `Job` because both are cheap to derive and their thresholds are *settings* — computing at
/// read time means changing a threshold re-filters the list instantly, with no recompute pass and no
/// schema change. (Location stays stored: it's computed once from the extraction.)
///
/// Absent data never fails a requirement. A posting that doesn't publish a band is unknown, not
/// disqualified, so it lands in `.notStated` for separate triage — the same rule already applied to a
/// posting that doesn't state its work arrangement.
public enum JobRequirements {
    /// The user's configured floors. Zero disables a check, so an unconfigured install behaves exactly
    /// as it did before.
    public struct Thresholds: Equatable, Sendable {
        public let minSalary: Int
        public let minFitScore: Int

        public init(minSalary: Int, minFitScore: Int) {
            self.minSalary = minSalary
            self.minFitScore = minFitScore
        }

        public static let none = Thresholds(minSalary: 0, minFitScore: 0)
    }

    /// One requirement's outcome, in two lengths: `short` rides inline on the badge so the reason is
    /// visible without hovering, `long` is the full sentence for the tooltip.
    public struct Reason: Equatable, Sendable {
        public let short: String
        public let long: String

        public init(short: String, long: String) {
            self.short = short
            self.long = long
        }
    }

    /// What a job was measured against and how it fared.
    public struct Verdict: Equatable, Sendable {
        public let bucket: JobFilterRules.CriteriaBucket
        /// Requirements the job definitively failed.
        public let failures: [Reason]
        /// Requirements that couldn't be judged because the posting didn't say.
        public let unstated: [Reason]

        /// The reasons that decided the bucket — failures when there are any, otherwise the gaps.
        private var deciding: [Reason] {
            failures.isEmpty ? unstated : failures
        }

        /// Full sentence(s) for the tooltip.
        public var summary: String {
            deciding.isEmpty ? "Meets your requirements" : deciding.map(\.long).joined(separator: " · ")
        }

        /// Compact form for the badge itself, e.g. "fit 44 < 50".
        public var shortSummary: String? {
            deciding.isEmpty ? nil : deciding.map(\.short).joined(separator: ", ")
        }

        /// What the badge reads. The reason replaces the bucket label rather than being appended to
        /// it — the icon already distinguishes pass / unknown / fail, and prefixing produced
        /// "Arrangement not stated: arrangement not stated" for the location case.
        public func badgeText(_ label: String) -> String {
            shortSummary ?? label
        }
    }

    /// The salary figure a job is judged on: the TOP of its range, so a posting is only rejected when
    /// even its ceiling falls short. Falls back to the single/minimum figure when no maximum is given.
    public static func comparableSalary(min: Int?, max: Int?) -> Int? {
        for value in [max, min] {
            if let value, value > 0 { return value }
        }
        return nil
    }

    /// Evaluate a job. Returns nil when the location verdict was never computed (extraction failed),
    /// matching `criteriaBucket`'s existing contract so those jobs match no bucket.
    public static func evaluate(
        meetsCriteria: Bool?,
        remoteType: RemoteType?,
        salaryMin: Int?,
        salaryMax: Int?,
        salaryCurrency: String?,
        fitScore: Int?,
        thresholds: Thresholds
    ) -> Verdict? {
        guard let locationBucket = JobFilterRules.criteriaBucket(
            meetsCriteria: meetsCriteria, remoteType: remoteType
        ) else { return nil }

        var failures: [Reason] = []
        var unstated: [Reason] = []

        switch locationBucket {
        case .doesNotMeet:
            failures.append(Reason(short: "Location outside your criteria", long: "Location outside your criteria"))
        case .notStated:
            unstated.append(Reason(short: "Work arrangement not stated", long: "Work arrangement not stated"))
        case .meets:
            break
        }

        if thresholds.minSalary > 0 {
            let currency = (salaryCurrency ?? "").uppercased()
            if !currency.isEmpty, currency != "USD" {
                // Comparing a foreign figure against a USD floor would be meaningless, not merely
                // imprecise — treat it as unknown rather than converting at an invented rate.
                unstated.append(Reason(
                    short: "Salary in \(currency) — not comparable",
                    long: "Salary in \(currency) — not comparable"
                ))
            } else if let salary = comparableSalary(min: salaryMin, max: salaryMax) {
                if salary < thresholds.minSalary {
                    failures.append(Reason(
                        short: "Pays ≤ \(money(salary)), under your \(money(thresholds.minSalary)) floor",
                        long: "Pays up to \(money(salary)), below your \(money(thresholds.minSalary)) floor"
                    ))
                }
            } else {
                unstated.append(Reason(short: "No salary stated", long: "No salary stated"))
            }
        }

        if thresholds.minFitScore > 0 {
            if let fitScore {
                if fitScore < thresholds.minFitScore {
                    failures.append(Reason(
                        short: "Fit \(fitScore), under your minimum of \(thresholds.minFitScore)",
                        long: "Fit \(fitScore), below your minimum of \(thresholds.minFitScore)"
                    ))
                }
            } else {
                unstated.append(Reason(short: "Not scored yet", long: "Not scored yet"))
            }
        }

        // A definite failure outranks a gap in the data: one requirement it demonstrably misses is
        // enough, whatever else is unknown.
        let bucket: JobFilterRules.CriteriaBucket = if !failures.isEmpty {
            .doesNotMeet
        } else if !unstated.isEmpty {
            .notStated
        } else {
            .meets
        }
        return Verdict(bucket: bucket, failures: failures, unstated: unstated)
    }

    /// "$200k" / "$185k" — compact enough for a chip or a one-line reason.
    static func money(_ value: Int) -> String {
        value >= 1000 ? "$\(value / 1000)k" : "$\(value)"
    }
}
