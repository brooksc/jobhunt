import Foundation
import SwiftData

/// How a source's last run went.
///
/// `empty` is a *success* — the board answered, it just had nothing. It is nonetheless the state
/// worth watching, because a board that migrated ATS looks exactly like this and never recovers on
/// its own. `truncated` is its own case for the same reason in reverse: a sweep that stopped on a
/// rate limit found real postings, and filing it as `ok` would hide an incomplete listing.
public enum SearchSourceStatus: String, Sendable, Equatable, CaseIterable {
    case never
    case ok
    case empty
    case truncated
    case unreachable
    case rateLimited
    case misconfigured

    /// Whether the user needs to do something. Drives the coloured dot.
    public var needsAttention: Bool {
        switch self {
        case .never, .ok: false
        case .empty, .truncated: true
        case .unreachable, .rateLimited, .misconfigured: true
        }
    }
}

/// One board jobhunt sweeps on a schedule (TASK-692, M3).
///
/// **Deliberately not an extension of `Site`.** `Site` is a human-review reminder — it has
/// `SiteReview`, `SiteReviewBucket`, a `state`, a unique `origin`, and a cadence measured in days
/// because a person is doing the looking. This has a machine consumer, an hourly cadence, and
/// health fields that only make sense for something that runs unattended. Folding them together
/// would give both concepts a pile of fields the other never sets.
@Model
public final class SearchSource {
    public var id: String
    /// `JobSource.id` — "greenhouse", "lever", "ashby", "workday".
    public var kind: String
    /// What the user calls it. Defaults to the company name.
    public var label: String
    /// `SourceConfig`, JSON-encoded. A slug for most vendors, a board URL for Workday.
    public var configJSON: String
    public var enabled: Bool
    public var intervalHours: Int

    public var lastRunAt: Date?
    public var nextRunAt: Date?
    public var lastStatusRaw: String
    /// A human-readable failure, when there was one. Never a raw error dump — this reaches the UI.
    public var lastError: String?

    /// The count that catches a silent migration. Three in a row means the board almost certainly
    /// moved, and the UI says so rather than waiting for the user to notice they've had no results
    /// for a month.
    public var consecutiveEmptyRuns: Int

    public var lastFoundCount: Int
    public var lastPassedCount: Int
    public var lastIngestedCount: Int

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: String,
        label: String,
        config: SourceConfig,
        enabled: Bool = true,
        intervalHours: Int = 12,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        configJSON = SearchSource.encode(config) ?? "{}"
        self.enabled = enabled
        self.intervalHours = intervalHours
        lastRunAt = nil
        // Due immediately: a source the user just added should produce something without them
        // wondering whether it's working.
        nextRunAt = createdAt
        lastStatusRaw = SearchSourceStatus.never.rawValue
        lastError = nil
        consecutiveEmptyRuns = 0
        lastFoundCount = 0
        lastPassedCount = 0
        lastIngestedCount = 0
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    public var status: SearchSourceStatus {
        SearchSourceStatus(rawValue: lastStatusRaw) ?? .never
    }

    public var config: SourceConfig {
        get { SearchSource.decode(configJSON) ?? SourceConfig(slug: "") }
        set { configJSON = SearchSource.encode(newValue) ?? configJSON }
    }

    public var source: (any JobSource)? {
        JobSources.source(id: kind)
    }

    /// Whether this source is due, given the clock.
    ///
    /// A disabled source is never due — the global toggle and the per-source toggle both have to
    /// stop all activity within one cycle, and doing that here means no caller can forget.
    public func isDue(now: Date = Date()) -> Bool {
        guard enabled else { return false }
        guard let next = nextRunAt else { return true }
        return next <= now
    }

    /// Record the result of a run and schedule the next one.
    ///
    /// `consecutiveEmptyRuns` resets on any run that found something, including a truncated one —
    /// a rate limit says nothing about whether the board moved.
    public func recordRun(
        status: SearchSourceStatus,
        found: Int = 0,
        passed: Int = 0,
        ingested: Int = 0,
        error: String? = nil,
        now: Date = Date()
    ) {
        lastRunAt = now
        nextRunAt = now.addingTimeInterval(Double(max(1, intervalHours)) * 3600)
        lastStatusRaw = status.rawValue
        lastError = error
        lastFoundCount = found
        lastPassedCount = passed
        lastIngestedCount = ingested
        consecutiveEmptyRuns = status == .empty ? consecutiveEmptyRuns + 1 : 0
        updatedAt = now
    }

    /// Three consecutive empty runs. Not proof the board moved, but the point at which guessing is
    /// better than continuing to say nothing.
    public var looksMigrated: Bool {
        consecutiveEmptyRuns >= 3
    }

    static func encode(_ config: SourceConfig) -> String? {
        guard let data = try? JSONEncoder().encode(config) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String) -> SourceConfig? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SourceConfig.self, from: data)
    }
}
