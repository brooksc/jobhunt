import Foundation
import SwiftData

// MARK: - Rubric-version bookkeeping (TASK-711)

//
// `assessment_prompt_version` used to live only inside `fitScoreJSON`, so nothing could answer "which
// scores are not on the current rubric?" without parsing every blob. `JobFitScore.assessmentPromptVersion`
// mirrors it into a real column; these operations fill that column in, report on it, and pick out the
// work set for a rescore. All three are driven from `JobhuntMigrator` — one-time data work, never the
// app's launch path.

public extension BackgroundStore {
    /// One rubric version and how many stored scores carry it. `version` is nil for rows whose
    /// analysis records no version at all.
    struct FitScoreVersionCount: Sendable, Equatable {
        public let version: Int?
        public let count: Int
        public let meanScore: Double?
    }

    /// A stored score that needs re-running against the current rubric.
    struct StaleFitScore: Sendable, Equatable {
        public let jobID: String
        public let resumeID: String
        public let jobNumber: Int?
        public let jobTitle: String
        /// The rubric this score was assessed under; nil when the row records none.
        public let version: Int?
    }

    /// Fill `assessmentPromptVersion` from each row's stored analysis. No LLM calls.
    ///
    /// Idempotent: a row whose column already agrees with its JSON is skipped, so a re-run reports 0
    /// updated. Rows whose JSON carries no version keep a nil column — nil means *unknown*, and
    /// inventing v1 for them would make three unversioned rows indistinguishable from 977 genuine v1s.
    func backfillFitScorePromptVersions() throws -> (updated: Int, unversioned: Int) {
        var updated = 0
        var unversioned = 0
        for record in try modelContext.fetch(FetchDescriptor<JobFitScore>()) {
            let parsed = FitScorer.promptVersion(inJSON: record.fitScoreJSON)
            if parsed == nil { unversioned += 1 }
            guard record.assessmentPromptVersion != parsed else { continue }
            record.assessmentPromptVersion = parsed
            updated += 1
        }
        if updated > 0 {
            try modelContext.save()
        }
        return (updated, unversioned)
    }

    /// Count (and mean score) per rubric version, ordered oldest first with the unversioned rows last.
    ///
    /// Reads the column, not the JSON — so run `backfillFitScorePromptVersions()` first, or the
    /// histogram reports every pre-existing row as unversioned.
    func fitScorePromptVersionHistogram() throws -> [FitScoreVersionCount] {
        var buckets: [Int?: [Int?]] = [:]
        for record in try modelContext.fetch(FetchDescriptor<JobFitScore>()) {
            buckets[record.assessmentPromptVersion, default: []].append(record.fitScore)
        }
        return buckets
            .map { version, scores in
                let numeric = scores.compactMap(\.self)
                let mean = numeric.isEmpty
                    ? nil
                    : Double(numeric.reduce(0, +)) / Double(numeric.count)
                return FitScoreVersionCount(version: version, count: scores.count, meanScore: mean)
            }
            // Unversioned last: `nil` isn't ordered against the integers, and it reads as "the rest".
            .sorted { ($0.version ?? Int.max) < ($1.version ?? Int.max) }
    }

    /// Every succeeded score not assessed under `currentVersion`, in job-number order.
    ///
    /// Scores without a résumé are skipped — there is nothing to re-score them against, and
    /// `--prune-orphan-fit-scores` is the mode that deals with those.
    func staleFitScores(currentVersion: Int = FitScorer.assessmentPromptVersion) throws -> [StaleFitScore] {
        try modelContext.fetch(FetchDescriptor<JobFitScore>())
            .filter { $0.fitStatus == .succeeded && $0.assessmentPromptVersion != currentVersion }
            .compactMap { record in
                guard let job = record.job, let resume = record.resume else { return nil }
                return StaleFitScore(
                    jobID: job.id,
                    resumeID: resume.id,
                    jobNumber: job.jobNumber,
                    jobTitle: job.title ?? "(untitled)",
                    version: record.assessmentPromptVersion
                )
            }
            .sorted { ($0.jobNumber ?? 0) < ($1.jobNumber ?? 0) }
    }

    /// Persist a freshly-scored fit result over the existing record for this job/résumé pair.
    ///
    /// Committed one score at a time on purpose: a rescore run costs real money per call, so an
    /// interrupted run must keep everything it already paid for. Each commit moves that row onto the
    /// current version, which is also what takes it out of `staleFitScores` on the next run — that is
    /// the whole of the resume mechanism.
    func commitRescoredFitScore(
        jobID: String,
        resumeID: String,
        output: FitScoreOutput,
        scoredAt: Date = Date()
    ) throws {
        try applyFitScore(
            jobID: jobID,
            resumeID: resumeID,
            overall: output.score.overall,
            fitJSON: output.fitScoreJSON ?? FitScorer.encode(output.score),
            model: output.modelReturned,
            scoredAt: scoredAt
        )
        try modelContext.save()
    }

    /// The scoring settings a command-line rescore needs. API keys are deliberately absent: they live
    /// in the Keychain under the app's access control, so the CLI takes one from the environment.
    struct StoredScoringConfig: Sendable {
        public let provider: String
        public let model: String
        public let baseURL: String
        public let timeoutSeconds: Int
    }

    func storedScoringConfig() throws -> StoredScoringConfig {
        let rows = try modelContext.fetch(FetchDescriptor<Setting>())
        let byKey = Dictionary(rows.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        return StoredScoringConfig(
            provider: byKey[SettingsKey.llmProvider] ?? "lmstudio",
            model: byKey[SettingsKey.llmModel] ?? "",
            baseURL: byKey[SettingsKey.llmBaseURL] ?? "",
            timeoutSeconds: byKey[SettingsKey.llmTimeout].flatMap(Int.init) ?? 300
        )
    }

    /// The corrections the user has recorded, for a caller outside the app (the migrator) that has no
    /// `SettingsStore`.
    func scoringFeedbackForRescore() throws -> [ScoringFeedback] {
        try storedScoringFeedback()
    }
}
