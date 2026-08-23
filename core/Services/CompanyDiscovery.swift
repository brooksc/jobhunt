import Foundation
import SwiftData

/// A company worth watching that isn't being watched yet.
public struct CompanySuggestion: Sendable, Equatable, Identifiable {
    public var id: String {
        "\(board.kind):\(board.slug)"
    }

    /// The employer's name as jobhunt already knows it.
    public let company: String
    public let board: ResolvedBoard
    /// How many jobs from this company are already in the app — the evidence that the user cares.
    public let existingJobCount: Int
    /// Whether the board was found for free from a URL jobhunt already had, or had to be probed.
    public let resolvedFromExistingURL: Bool
}

/// Turns companies the user has already shown interest in into sources they can watch (TASK-695, M6).
///
/// **This is M6, redesigned around what the measurements said.** The original plan was to add
/// aggregator boards as market-wide sources. Measured on 2026-08-22, that framing doesn't survive:
/// aggregators carry ~5–20× more engineering than product/program work, one Swiss board accounted
/// for 79% of the sampled volume, and the four large English-language boards link to their own
/// pages rather than to any ATS. What *did* survive was the observation underneath the numbers —
/// the valuable thing an aggregator provides is not postings but **employers**.
///
/// And the best available list of employers a user cares about isn't an aggregator at all. It's the
/// jobs already in their app. Someone who captured a posting at Acme has demonstrated more interest
/// in Acme than any market-wide feed could infer, and jobhunt already holds the URL that names
/// Acme's ATS — so most suggestions cost **no network request at all**.
///
/// The leverage is the point: measured against real boards, a single captured posting at Databricks
/// turns into a source watching 821 open roles, continuously, without the user knowing what
/// Greenhouse is.
///
/// Deliberately does **not** filter by the user's title criteria. A company hiring engineers today
/// may post a program manager next month, and a source watches the whole board forever — filtering
/// at discovery time would throw away exactly the durable value.
public struct CompanyDiscovery: Sendable {
    let store: BackgroundStore
    let session: URLSession

    public init(store: BackgroundStore, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    /// Companies with jobs in the app that aren't yet watched as sources.
    ///
    /// - Parameter probeLimit: how many companies may be *probed* (the ones whose board can't be
    ///   read off a URL jobhunt already has). Bounded because each probe is up to three requests to
    ///   third-party APIs, and a first run on a large library would otherwise fan out hard.
    public func suggestions(probeLimit: Int = 15) async -> [CompanySuggestion] {
        guard let candidates = try? await store.untrackedCompanyCandidates() else { return [] }

        var suggestions: [CompanySuggestion] = []
        var probed = 0
        // Free first: a company whose jobs carry an ATS URL needs no probe, so ordering this way
        // means the probe budget is spent only on companies that actually need it.
        let (fromURL, needingProbe) = candidates.reduce(
            into: ([CompanyCandidate](), [CompanyCandidate]())
        ) { partial, candidate in
            if candidate.urls.contains(where: { SourceResolver.identify(boardURL: $0) != nil }) {
                partial.0.append(candidate)
            } else {
                partial.1.append(candidate)
            }
        }

        for candidate in fromURL {
            guard let board = candidate.urls.lazy
                .compactMap({ SourceResolver.identify(boardURL: $0) }).first else { continue }
            suggestions.append(CompanySuggestion(
                company: candidate.company, board: board,
                existingJobCount: candidate.jobCount, resolvedFromExistingURL: true
            ))
        }

        for candidate in needingProbe {
            guard probed < probeLimit else { break }
            probed += 1
            if case let .resolved(board) = await SourceResolver.resolve(
                companyName: candidate.company, session: session
            ) {
                suggestions.append(CompanySuggestion(
                    company: candidate.company, board: board,
                    existingJobCount: candidate.jobCount, resolvedFromExistingURL: false
                ))
            }
        }

        // Most-evidence first: the companies the user has captured most from are the ones they're
        // most likely to want watched.
        return suggestions.sorted {
            $0.existingJobCount == $1.existingJobCount
                ? $0.company.localizedCaseInsensitiveCompare($1.company) == .orderedAscending
                : $0.existingJobCount > $1.existingJobCount
        }
    }
}

/// A company in the library, with the URLs jobhunt has for it.
public struct CompanyCandidate: Sendable, Equatable {
    public let company: String
    public let jobCount: Int
    /// Capture URLs, newest first. Only used to read a board identity off one, so a handful is
    /// plenty — an employer's tenth posting names the same ATS as its first.
    public let urls: [String]

    public init(company: String, jobCount: Int, urls: [String]) {
        self.company = company
        self.jobCount = jobCount
        self.urls = urls
    }
}

public extension BackgroundStore {
    /// Companies that have jobs but no `SearchSource` watching them.
    ///
    /// Matching is on a normalised name rather than an exact one: "Acme, Inc." in a job and "Acme"
    /// on a source are the same employer, and suggesting a company the user already watches is the
    /// fastest way to make the whole feature feel broken.
    func untrackedCompanyCandidates(maxURLsPerCompany: Int = 3) throws -> [CompanyCandidate] {
        let sources = try modelContext.fetch(FetchDescriptor<SearchSource>())
        var watched = Set(sources.map { CompanyNameKey.normalize($0.label) })
        for source in sources {
            if let company = source.config.company {
                watched.insert(CompanyNameKey.normalize(company))
            }
            // A source's slug is often the company name with the punctuation gone, which is exactly
            // what normalisation produces — so this catches a source added by URL, whose label may
            // be nothing but the slug.
            watched.insert(CompanyNameKey.normalize(source.config.slug))
        }
        watched.remove("")

        var byCompany: [String: (name: String, count: Int, urls: [String])] = [:]
        for job in try modelContext.fetch(FetchDescriptor<Job>()) {
            guard let company = job.company?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !company.isEmpty else { continue }
            let key = CompanyNameKey.normalize(company)
            guard !key.isEmpty, !watched.contains(key) else { continue }

            var entry = byCompany[key] ?? (company, 0, [])
            entry.count += 1
            if let url = job.capture?.url, !url.isEmpty, entry.urls.count < maxURLsPerCompany {
                entry.urls.append(url)
            }
            byCompany[key] = entry
        }

        return byCompany.values
            .map { CompanyCandidate(company: $0.name, jobCount: $0.count, urls: $0.urls) }
            .sorted { $0.jobCount > $1.jobCount }
    }
}

/// One definition of "the same employer", so the suggestion list and the watched list can't
/// disagree about it.
public enum CompanyNameKey {
    /// Legal suffixes carry no identity — "Acme" and "Acme, Inc." are one company, and treating
    /// them as two would suggest a company the user already watches.
    static let suffixes: Set<String> = [
        "inc", "llc", "ltd", "limited", "gmbh", "corp", "corporation", "co", "sa", "ag",
        "bv", "plc", "group", "holdings", "labs", "technologies", "the"
    ]

    public static func normalize(_ name: String) -> String {
        let words = name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !suffixes.contains($0) }
        return words.joined()
    }
}
