import Foundation
import SwiftData

public enum SiteServiceError: Error, Sendable {
    case siteNotFound(String)
}

public actor SiteService {
    private let store: BackgroundStore

    public init(store: BackgroundStore) {
        self.store = store
    }

    // MARK: - Upsert from extension POST /site-reviews

    /// Upsert a SiteReview from the extension payload.
    /// Also upserts the corresponding Site record.
    /// Returns the site_review_id.
    public func upsertSiteReview(url: String, title: String?, intervalDays: Int) async throws -> String {
        guard let parsedURL = URL(string: url), let origin = parsedURL.origin else {
            // Fall back to using the full URL as origin
            return try await upsertSiteReviewInternal(url: url, origin: url, title: title, intervalDays: intervalDays)
        }
        return try await upsertSiteReviewInternal(url: url, origin: origin, title: title, intervalDays: intervalDays)
    }

    private func upsertSiteReviewInternal(
        url: String,
        origin: String,
        title: String?,
        intervalDays: Int
    ) async throws -> String {
        let now = Date()
        let nextReviewAt = Calendar.current.date(byAdding: .day, value: intervalDays, to: now)

        // Upsert the Site record
        let sites = try await store.fetch(FetchDescriptor<Site>())
        if let existing = sites.first(where: { $0.origin == origin }) {
            // Update site review timing
            let siteID = existing.id
            try await store.update(Site.self, predicate: #Predicate { $0.id == siteID }) { site in
                site.lastReviewedAt = now
                site.nextReviewAt = nextReviewAt
                site.intervalDays = intervalDays
                if let title { site.pageTitle = title }
                site.state = .reviewed
                site.updatedAt = now
            }
        } else {
            // Create a new Site
            let site = Site(
                origin: origin,
                url: url,
                pageTitle: title ?? "",
                intervalDays: intervalDays,
                lastReviewedAt: now,
                nextReviewAt: nextReviewAt,
                state: .reviewed
            )
            try await store.insert(site)
        }

        // Create a SiteReview record
        let review = SiteReview(
            siteURL: url,
            siteOrigin: origin,
            pageTitle: title,
            reviewedAt: now,
            nextReviewAt: nextReviewAt
        )
        try await store.insert(review)
        return review.id
    }

    // MARK: - CRUD

    public func createSite(url: String, name: String?) async throws -> String {
        let origin = URL(string: url)?.origin ?? url
        let site = Site(
            origin: origin,
            url: url,
            companyName: name
        )
        try await store.insert(site)
        return site.id
    }

    public func updateSite(id: String, name: String?, excludeState: SiteState?, intervalDays: Int? = nil) async throws {
        let siteID = id
        try await store.update(Site.self, predicate: #Predicate { $0.id == siteID }) { site in
            if let name { site.companyName = name }
            if let state = excludeState { site.state = state }
            if let days = intervalDays { site.intervalDays = days }
            site.updatedAt = Date()
        }
    }

    public func deleteSite(id: String) async throws {
        let siteID = id
        try await store.delete(Site.self, predicate: #Predicate { $0.id == siteID })
    }

    // MARK: - Review scheduling

    /// Sets last_reviewed_at and calculates next_review_at from the site's intervalDays.
    public func markReviewed(siteID: String) async throws {
        let id = siteID
        let sites = try await store.fetch(FetchDescriptor<Site>(predicate: #Predicate { $0.id == id }))
        guard let site = sites.first else { throw SiteServiceError.siteNotFound(siteID) }
        let intervalDays = site.intervalDays
        let now = Date()
        let next = Calendar.current.date(byAdding: .day, value: intervalDays, to: now)
        try await store.update(Site.self, predicate: #Predicate { $0.id == id }) { site in
            site.lastReviewedAt = now
            site.nextReviewAt = next
            site.state = .reviewed
            site.updatedAt = now
        }
    }

    public func setSiteState(siteID: String, state: SiteState) async throws {
        let id = siteID
        try await store.update(Site.self, predicate: #Predicate { $0.id == id }) { site in
            site.state = state
            site.updatedAt = Date()
        }
    }
}

// MARK: - URL origin helper

private extension URL {
    /// Returns the scheme + "://" + host (+ optional port) string, matching the browser's `location.origin`.
    var origin: String? {
        guard let scheme = self.scheme, let host = self.host else { return nil }
        if let port = self.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}
