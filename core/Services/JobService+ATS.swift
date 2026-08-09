import Foundation
import SwiftData

/// Authoritative posting lookups against the employer's ATS (TASK-632/633/634/635, generalized to
/// any provider by TASK-636).
///
/// Split out of `JobService.swift`, which this pushed past the file-length limit.
public extension JobService {
    /// Pulls the canonical posting from whichever ATS published it and replaces the scraped capture
    /// with it, optionally re-running extraction on the better text.
    ///
    /// Explicit and per-job by design. For Greenhouse the board slug is a *guess*, so this can fetch
    /// the wrong company's posting when a career-site host and a company name both mislead. That's
    /// tolerable when a person asked for it on one job and can see the result; it would not be
    /// tolerable as a silent background sweep.
    ///
    /// Every failure is soft rather than thrown, so an unreachable board leaves the existing capture
    /// untouched — the failure to avoid is overwriting a usable description with an error page.
    func refreshFromATS(
        jobID: String,
        reextract: Bool = true,
        session: URLSession = .shared
    ) async -> Result<BackgroundStore.GreenhouseRefreshOutcome, GreenhouseJobBoard.RefreshError> {
        guard let identity = try? await store.atsIdentity(jobID: jobID) ?? nil else {
            return .failure(.notGreenhouse)
        }

        guard let posting = await identity.provider.fetchPosting(
            atsID: identity.atsID,
            company: identity.company,
            urlString: identity.urlString,
            session: session
        ) else {
            return .failure(.boardNotResolved)
        }

        guard let outcome = try? await store.applyATSRefresh(jobID: jobID, posting: posting) else {
            return .failure(.malformedResponse)
        }

        // Only re-extract when the text actually changed: re-running the model over an identical
        // description spends money to reproduce the answer already on screen.
        if reextract, outcome.descriptionChanged {
            try? await resetExtraction(jobID: jobID)
        }
        return .success(outcome)
    }

    /// Every other open role on the same board, ranked against this job (TASK-634).
    ///
    /// Returns an empty list on any failure — a discovery aid shouldn't interrupt the user when a
    /// board is unreachable.
    func openRolesAtSameCompany(
        jobID: String,
        session: URLSession = .shared
    ) async -> [OpenRoleRelevance.Scored] {
        guard let identity = try? await store.atsIdentity(jobID: jobID) ?? nil else { return [] }

        async let rolesTask = identity.provider.listOpenRoles(
            atsID: identity.atsID, company: identity.company,
            urlString: identity.urlString, session: session
        )
        async let postingTask = identity.provider.fetchPosting(
            atsID: identity.atsID, company: identity.company,
            urlString: identity.urlString, session: session
        )
        let (roles, posting) = await (rolesTask, postingTask)

        return OpenRoleRelevance.rank(
            roles: roles,
            title: posting?.title,
            location: posting?.locationName,
            // Drop the posting the user is already looking at.
            excludingURLs: Set([posting?.absoluteURL, identity.urlString].compactMap(\.self))
        )
    }

    /// What this job's application form will ask for (TASK-635), or nil when the vendor doesn't
    /// publish it — only Greenhouse does today. Read-only; nothing here submits anything.
    func applicationFormPreview(
        jobID: String,
        session: URLSession = .shared
    ) async -> ApplicationFormPreview? {
        guard let identity = try? await store.atsIdentity(jobID: jobID) ?? nil else { return nil }
        return await identity.provider.fetchApplicationForm(
            atsID: identity.atsID, company: identity.company,
            urlString: identity.urlString, session: session
        )
    }
}
