import Foundation
import SwiftData

public enum SiteServiceError: Error, LocalizedError, Sendable {
    case siteNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .siteNotFound: "Site not found"
        }
    }
}

public actor SiteService {
    private let store: BackgroundStore

    public init(store: BackgroundStore) {
        self.store = store
    }

    // MARK: - Upsert from extension POST /site-reviews

    /// Upsert a SiteReview from the extension payload (new format: explicit reviewed_at / next_review_at).
    /// `origin` is taken from the `site_origin` field when provided; otherwise derived from the URL.
    /// Returns the site_review_id.
    public func upsertSiteReview(
        url: String,
        origin explicitOrigin: String?,
        title: String?,
        note: String?,
        reviewedAt: Date,
        nextReviewAt: Date?
    ) async throws -> String {
        let origin: String
        if let o = explicitOrigin, !o.isEmpty {
            origin = o
        } else if let parsedURL = URL(string: url), let derived = parsedURL.origin {
            origin = derived
        } else {
            origin = url
        }
        // Derive a pseudo-intervalDays from the gap so the Site record remains consistent.
        let intervalDays: Int
        if let next = nextReviewAt {
            let days = Calendar.current.dateComponents([.day], from: reviewedAt, to: next).day ?? 14
            intervalDays = max(1, days)
        } else {
            intervalDays = 14
        }
        return try await upsertSiteReviewInternal(
            url: url,
            origin: origin,
            title: title,
            intervalDays: intervalDays,
            reviewedAt: reviewedAt,
            nextReviewAt: nextReviewAt ?? Calendar.current.date(byAdding: .day, value: intervalDays, to: reviewedAt),
            note: note
        )
    }

    /// Upsert a SiteReview from the extension payload (legacy format: interval_days).
    /// Also upserts the corresponding Site record.
    /// Returns the site_review_id.
    public func upsertSiteReview(
        url: String,
        title: String?,
        intervalDays: Int,
        note: String? = nil
    ) async throws -> String {
        guard let parsedURL = URL(string: url), let origin = parsedURL.origin else {
            // Fall back to using the full URL as origin
            return try await upsertSiteReviewInternal(
                url: url,
                origin: url,
                title: title,
                intervalDays: intervalDays,
                note: note
            )
        }
        return try await upsertSiteReviewInternal(
            url: url,
            origin: origin,
            title: title,
            intervalDays: intervalDays,
            note: note
        )
    }

    private func upsertSiteReviewInternal(
        url: String,
        origin: String,
        title: String?,
        intervalDays: Int,
        reviewedAt: Date? = nil,
        nextReviewAt: Date? = nil,
        note: String? = nil
    ) async throws -> String {
        // Reject non-http(s) site URLs at ingestion so a forged /site-reviews payload can't later hand a
        // file:// or custom-scheme URL to NSWorkspace.open when the user clicks "Visit Site" (F16).
        // Mirrors the URL policy JobService.ingestCapture already applies to captured jobs.
        let validatedURL = try URLNormalizer.validatedForIngestion(url)
        let now = reviewedAt ?? Date()
        let next = nextReviewAt ?? Calendar.current.date(byAdding: .day, value: intervalDays, to: now)

        // Upsert the Site record
        let sites = try await store.fetch(FetchDescriptor<Site>())
        if let existing = sites.first(where: { $0.origin == origin }) {
            // Update site review timing
            let siteID = existing.id
            try await store.update(Site.self, predicate: #Predicate { $0.id == siteID }) { site in
                site.lastReviewedAt = now
                site.nextReviewAt = next
                site.intervalDays = intervalDays
                if let title { site.pageTitle = title }
                site.state = .reviewed
                site.updatedAt = now
            }
        } else {
            // Create a new Site
            let site = Site(
                origin: origin,
                url: validatedURL,
                pageTitle: title ?? "",
                intervalDays: intervalDays,
                lastReviewedAt: now,
                nextReviewAt: next,
                state: .reviewed
            )
            try await store.insert(site)
        }

        // Create a SiteReview record
        let review = SiteReview(
            siteURL: validatedURL,
            siteOrigin: origin,
            pageTitle: title,
            reviewedAt: now,
            nextReviewAt: next,
            note: note
        )
        // Read the id BEFORE the transfer. `insert` moves the model into the store's ModelContext,
        // and reading it back here would read a row this isolation no longer owns (TASK-692).
        let reviewID = review.id
        try await store.insert(review)
        return reviewID
    }

    // MARK: - CRUD

    public func createSite(url: String, name: String?, intervalDays: Int = 14) async throws -> String {
        let origin = URL(string: url)?.origin ?? url
        let sites = try await store.fetch(FetchDescriptor<Site>())
        if let existing = sites.first(where: { $0.origin == origin }) {
            if let name {
                let siteID = existing.id
                try await store.updateOne(Site.self, predicate: #Predicate { $0.id == siteID }, id: siteID) { site in
                    site.companyName = name
                    site.updatedAt = Date()
                }
            }
            return existing.id
        }
        let site = Site(origin: origin, url: url, companyName: name, intervalDays: intervalDays, nextReviewAt: nil)
        // As above: the id is read before ownership of the model passes to the store.
        let siteID = site.id
        try await store.insert(site)
        return siteID
    }

    public func updateSite(
        id: String,
        name: String? = nil,
        excludeState: SiteState? = nil,
        intervalDays: Int? = nil,
        note: String? = nil,
        companyWebsite: String? = nil,
        jobsURL: String? = nil,
        companyDescription: String? = nil
    ) async throws {
        let siteID = id
        try await store.updateOne(Site.self, predicate: #Predicate { $0.id == siteID }, id: id) { site in
            if let name { site.companyName = name }
            if let state = excludeState { site.state = state }
            if let days = intervalDays {
                site.intervalDays = days
                let base = site.lastReviewedAt ?? Date()
                site.nextReviewAt = Calendar.current.date(byAdding: .day, value: days, to: base)
            }
            if let note { site.note = note }
            if let companyWebsite { site.companyWebsite = companyWebsite }
            if let jobsURL { site.jobsURL = jobsURL }
            if let companyDescription { site.companyDescription = companyDescription }
            site.updatedAt = Date()
        }
    }

    /// Set an explicit next-review date offset from today, independent of the recurring interval.
    public func setNextReview(id: String, daysFromNow: Int) async throws {
        let siteID = id
        try await store.updateOne(Site.self, predicate: #Predicate { $0.id == siteID }, id: id) { site in
            site.nextReviewAt = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())
            site.updatedAt = Date()
        }
    }

    public func deleteSite(id: String) async throws {
        let siteID = id
        try await store.deleteOne(Site.self, predicate: #Predicate { $0.id == siteID }, id: id)
    }

    // MARK: - Review scheduling

    /// Sets last_reviewed_at and calculates next_review_at from the site's intervalDays.
    public func markReviewed(siteID: String) async throws {
        let id = siteID
        let sites = try await store.fetch(FetchDescriptor<Site>(predicate: #Predicate { $0.id == id }))
        guard let site = sites.first else { throw SiteServiceError.siteNotFound(siteID) }
        let intervalDays = site.intervalDays
        let siteURL = site.url
        let siteOrigin = site.origin
        let pageTitle = site.pageTitle
        let now = Date()
        let next = Calendar.current.date(byAdding: .day, value: intervalDays, to: now)
        try await store.update(Site.self, predicate: #Predicate { $0.id == id }) { site in
            site.lastReviewedAt = now
            site.nextReviewAt = next
            site.state = .reviewed
            site.updatedAt = now
        }
        // Create SiteReview record for audit history
        let review = SiteReview(
            siteURL: siteURL,
            siteOrigin: siteOrigin,
            pageTitle: pageTitle.isEmpty ? nil : pageTitle,
            reviewedAt: now,
            nextReviewAt: next
        )
        try await store.insert(review)
    }

    public func setSiteState(siteID: String, state: SiteState) async throws {
        let id = siteID
        try await store.updateOne(Site.self, predicate: #Predicate { $0.id == id }, id: siteID) { site in
            site.state = state
            site.updatedAt = Date()
        }
    }

    // MARK: - MCP read queries

    public func listSites() async throws -> [SiteListRecord] {
        let descriptor = FetchDescriptor<Site>(
            sortBy: [SortDescriptor(\Site.createdAt, order: .reverse)]
        )
        let sites = try await store.fetch(descriptor)
        return sites.map { SiteListRecord(site: $0) }
    }
}

// MARK: - URL origin helper

private extension URL {
    /// Returns the scheme + "://" + host (+ optional port) string, matching the browser's `location.origin`.
    var origin: String? {
        guard let scheme, let host else { return nil }
        if let port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}
