import Foundation
import SwiftData

/// Refreshing a posting from the Greenhouse Job Board API (TASK-632).
///
/// Split out of `JobService.swift`, which this pushed past the file-length limit.
public extension JobService {
    /// Pulls a Greenhouse-backed job's canonical posting and replaces the scraped capture with it,
    /// optionally re-running extraction on the better text (TASK-632).
    ///
    /// Explicit and per-job by design: the board slug is a guess, so this can fetch the wrong
    /// company's posting if a career-site host and a company name both mislead. That's tolerable
    /// when a person asked for it on one job and can see the result; it would not be tolerable as a
    /// silent background sweep.
    ///
    /// Every failure is soft (`RefreshError`) rather than a thrown error, so an unreachable board
    /// leaves the existing capture untouched — the failure mode to avoid is overwriting a usable
    /// description with an error page.
    func refreshFromGreenhouse(
        jobID: String,
        reextract: Bool = true,
        session: URLSession = .shared
    ) async -> Result<BackgroundStore.GreenhouseRefreshOutcome, GreenhouseJobBoard.RefreshError> {
        guard let identity = try? await store.greenhouseIdentity(jobID: jobID) ?? nil else {
            return .failure(.notGreenhouse)
        }

        let fetched = await GreenhouseJobBoard.fetch(
            ghjid: identity.ghjid,
            company: identity.company,
            urlString: identity.urlString,
            session: session
        )
        guard case let .success(posting) = fetched else {
            return .failure((try? fetched.get()) == nil ? fetchError(fetched) : .malformedResponse)
        }

        guard let outcome = try? await store.applyGreenhouseRefresh(jobID: jobID, posting: posting)
        else {
            return .failure(.malformedResponse)
        }

        // Only re-extract when the text actually changed: re-running the model over an identical
        // description spends money to reproduce the answer already on screen.
        if reextract, outcome.descriptionChanged {
            try? await resetExtraction(jobID: jobID)
        }
        return .success(outcome)
    }

    private func fetchError(
        _ result: Result<GreenhouseJobBoard.Posting, GreenhouseJobBoard.RefreshError>
    ) -> GreenhouseJobBoard.RefreshError {
        if case let .failure(error) = result { return error }
        return .malformedResponse
    }
}
