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

    /// Every other open role on the same Greenhouse board, ranked against this job (TASK-634).
    ///
    /// Resolves the board by fetching this posting first rather than guessing again: a wrong slug
    /// would list another company's whole board, which is a confusing failure and a silent one.
    /// Returns an empty list on any failure — this is a discovery aid, not something to interrupt
    /// the user with when a board is unreachable.
    func openRolesAtSameCompany(
        jobID: String,
        session: URLSession = .shared
    ) async -> [OpenRoleRelevance.Scored] {
        guard let identity = try? await store.greenhouseIdentity(jobID: jobID) ?? nil else {
            return []
        }
        let posting = await GreenhouseJobBoard.fetch(
            ghjid: identity.ghjid,
            company: identity.company,
            urlString: identity.urlString,
            session: session
        )
        guard case let .success(resolved) = posting else { return [] }

        let roles = await GreenhouseJobBoard.listOpenRoles(board: resolved.board, session: session)
        return OpenRoleRelevance.rank(
            roles: roles,
            title: resolved.title,
            location: resolved.locationName,
            // Drop the posting the user is already looking at.
            excludingURLs: Set([resolved.absoluteURL, identity.urlString].compactMap(\.self))
        )
    }

    /// What this job's application form will ask for (TASK-635), or nil when the board doesn't
    /// publish it. Read-only — nothing here submits anything.
    func applicationFormPreview(
        jobID: String,
        session: URLSession = .shared
    ) async -> ApplicationFormPreview? {
        guard let identity = try? await store.greenhouseIdentity(jobID: jobID) ?? nil else {
            return nil
        }
        // Resolve the board through a posting fetch, same as the other board reads: a guessed slug
        // that happens to exist would show another company's application form.
        let posting = await GreenhouseJobBoard.fetch(
            ghjid: identity.ghjid,
            company: identity.company,
            urlString: identity.urlString,
            session: session
        )
        guard case let .success(resolved) = posting else { return nil }
        return await GreenhouseJobBoard.fetchApplicationForm(
            board: resolved.board, ghjid: identity.ghjid, session: session
        )
    }
}
