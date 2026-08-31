import Foundation
import JobhuntCore

// MARK: - Rescore scores left on a superseded rubric (TASK-711)

/// Per-score cost, measured rather than guessed: fit calls average 8,858 prompt / 1,351 completion
/// tokens, and `gemini-3.7-flash` bills $0.75/M in and $3.75/M out (introductory rate, through
/// 2026-12-31). Printed as an estimate before anything is sent, because this is the one migrator mode
/// that spends money — a full v1 sweep of 977 scores is about $11.44.
let measuredCostPerScore = 0.0117

/// Where the CLI gets the API key.
///
/// Not the Keychain: the app's key item is bound to the app's signing identity, so a separate
/// command-line binary reading it either fails or throws a GUI authorization prompt at the user — a
/// bad shape for an unattended bulk operation. The provider and model still come from the store, so
/// the rescore uses exactly the configuration the app is set to.
let apiKeyEnvironmentVariable = "JOBHUNT_API_KEY"

struct RescorePlan {
    let targets: [BackgroundStore.StaleFitScore]
    let config: BackgroundStore.StoredScoringConfig
}

/// Print the work set and what it will cost. Returns false when there is nothing to do.
func describeRescorePlan(_ plan: RescorePlan, currentVersion: Int) -> Bool {
    guard !plan.targets.isEmpty else {
        print("Every succeeded score is already on rubric v\(currentVersion) — nothing to rescore.")
        return false
    }
    var byVersion: [Int?: Int] = [:]
    for target in plan.targets {
        byVersion[target.version, default: 0] += 1
    }
    let breakdown = byVersion
        .sorted { ($0.key ?? Int.max) < ($1.key ?? Int.max) }
        .map { version, count in "\(count) on \(version.map { "v\($0)" } ?? "no recorded version")" }
        .joined(separator: ", ")
    let cost = Double(plan.targets.count) * measuredCostPerScore
    print("Stale scores: \(plan.targets.count) (\(breakdown)). Target rubric: v\(currentVersion).")
    print("Provider: \(plan.config.provider), model: \(plan.config.model.isEmpty ? "(unset)" : plan.config.model)")
    print(String(
        format: "Estimated cost: $%.2f (%d × $%.4f per score, measured).",
        cost,
        plan.targets.count,
        measuredCostPerScore
    ))
    return true
}

/// Re-run the LLM over each stale score, committing one at a time.
///
/// Resumable by construction: every commit stamps the current rubric version on that row, so an
/// interrupted run (or a `--limit`ed one) leaves the remainder still selected and a re-run picks up
/// exactly where it stopped. Nothing already paid for is redone.
func runRescore(
    plan: RescorePlan,
    store: BackgroundStore,
    feedback: [ScoringFeedback],
    apiKey: String
) async {
    let provider = LLMProviderFactory.makeProvider(
        provider: plan.config.provider,
        model: plan.config.model,
        baseURL: plan.config.baseURL,
        apiKey: apiKey,
        timeoutSeconds: plan.config.timeoutSeconds
    )
    var succeeded = 0
    var failed = 0
    for (index, target) in plan.targets.enumerated() {
        let label = "[\(index + 1)/\(plan.targets.count)] job #\(target.jobNumber.map(String.init) ?? "?")"
        do {
            guard let inputs = try await store.fitInputs(forJobID: target.jobID, resumeID: target.resumeID),
                  inputs.resumeExists,
                  !inputs.resumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("\(label) skipped — résumé missing or empty.")
                failed += 1
                continue
            }
            let output = try await ExtractionEngine.scoreFit(
                job: inputs.job,
                resume: ResumeSnapshot(text: inputs.resumeText),
                model: plan.config.model,
                provider: provider,
                feedback: feedback,
                jobNumber: target.jobNumber
            )
            try await store.commitRescoredFitScore(
                jobID: target.jobID, resumeID: target.resumeID, output: output
            )
            succeeded += 1
            let was = target.version.map { "v\($0)" } ?? "unversioned"
            print("\(label) \(target.jobTitle): \(was) → v\(FitScorer.assessmentPromptVersion), "
                + "score \(output.score.overall)")
        } catch {
            failed += 1
            // Keep going: one provider hiccup shouldn't abandon a run the user is paying for, and the
            // failed rows stay stale so the next run retries exactly them.
            print("\(label) FAILED: \(error)")
        }
    }
    print("Rescore complete: \(succeeded) rescored, \(failed) failed or skipped.")
    if failed > 0 {
        print("Re-run the same command to retry the failures — they are still on the old rubric.")
    }
}
