import Foundation

/// One board in the public directory.
public struct MarketBoard: Sendable, Equatable, Hashable {
    /// `JobSource.id`.
    public let kind: String
    /// What goes in `SourceConfig.slug` — a board slug, or a full URL for Workday.
    public let slug: String

    public init(kind: String, slug: String) {
        self.kind = kind
        self.slug = slug
    }
}

/// The public directory of ATS boards, so jobhunt can sweep the market rather than only the
/// companies a user thought to name (TASK-696).
///
/// **Why this exists.** Measured against career-ops' own output, 154 of 161 recent findings came
/// from companies the user does not track — only 4% of the employers that produced a match were on
/// their curated list. A tool that watches only what you name will miss almost everything, and the
/// user cannot name what they have never heard of. This is the list of what exists.
///
/// Sourced from `github.com/Feashliaa/job-board-aggregator` (MIT), the same dataset career-ops
/// uses. Four files, ~29,000 boards, about 600 KB. Cached locally and refreshed weekly: the value
/// is freshness — new boards appear constantly — but not same-day freshness.
///
/// **The dataset is untrusted input.** It is fetched from a third-party repository that tracks
/// `main`, so every entry is validated against a safe charset before it is interpolated into a URL,
/// and every finished URL is re-parsed to confirm its host is exactly the vendor's own. A tampered
/// dataset can therefore at worst name boards that don't exist.
public enum MarketDirectory {
    /// Raw files, by `JobSource.id`. iCIMS is in the dataset too and deliberately absent here —
    /// jobhunt has no iCIMS provider, and listing boards it cannot read would only produce failures.
    static let files: [(kind: String, file: String)] = [
        ("greenhouse", "greenhouse_companies.json"),
        ("lever", "lever_companies.json"),
        ("ashby", "ashby_companies.json"),
        ("workday", "workday_companies.json")
    ]

    static let base = "https://raw.githubusercontent.com/Feashliaa/job-board-aggregator/main/data"

    /// Weekly. The dataset's worth is that new boards appear, not that they appear today, and a
    /// daily re-download of 600 KB buys nothing a weekly one doesn't.
    public static let refreshInterval: TimeInterval = 7 * 24 * 3600

    // MARK: - Parsing

    /// Turn one dataset line into a board, or nil when it can't safely become a URL.
    ///
    /// Every rejection here is silent by design: the dataset carries thousands of entries, a few of
    /// which are malformed at any time, and a log line per bad row would bury the run.
    public static func board(kind: String, entry: String) -> MarketBoard? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if kind == "workday" {
            // `tenant|instance|site` triples. All three are interpolated, so all three are guarded —
            // but not identically. The tenant and instance become *DNS labels*, and a label cannot
            // contain a dot, so `evil.com|wd1|careers` must be refused: it would build
            // `evil.com.wd1.myworkdayjobs.com`, which is harmless (the suffix is always appended, so
            // nothing escapes the vendor domain) but can never resolve. The site is a path segment,
            // where a dot is ordinary.
            let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, parts.allSatisfy({ SourceResolver.isSafeSlug($0) }),
                  isHostLabel(parts[0]), isHostLabel(parts[1])
            else { return nil }
            let url = "https://\(parts[0]).\(parts[1]).myworkdayjobs.com/\(parts[2])"
            // Re-parse rather than trust the string by shape: the host must be exactly the tenant's
            // own, and must end at myworkdayjobs.com.
            guard let parsed = URL(string: url), let host = parsed.host?.lowercased(),
                  host == "\(parts[0]).\(parts[1]).myworkdayjobs.com".lowercased(),
                  host.hasSuffix(".myworkdayjobs.com")
            else { return nil }
            return MarketBoard(kind: kind, slug: url)
        }

        // Everything else is a bare slug, validated by the same guard the resolver uses and
        // confirmed by building the vendor URL and checking its host.
        guard SourceResolver.candidate(kind: kind, slug: trimmed) != nil else { return nil }
        return MarketBoard(kind: kind, slug: trimmed)
    }

    /// A single DNS label: no dots, and not empty. Used for the parts of a Workday entry that
    /// become subdomains.
    static func isHostLabel(_ part: String) -> Bool {
        !part.isEmpty && !part.contains(".")
    }

    /// Decode one dataset file. Accepts a bare JSON array of strings, which is what all four are.
    public static func decode(_ data: Data, kind: String) -> [MarketBoard] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { entry in
            guard let text = entry as? String else { return nil }
            return board(kind: kind, entry: text)
        }
    }

    // MARK: - Cache

    /// Beside the store, so a backup that captures Application Support captures this too — though
    /// losing it costs only a re-download.
    public static func cacheDirectory() -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return support.appending(path: "Jobhunt/market-directory", directoryHint: .isDirectory)
    }

    static func cacheURL(file: String) -> URL? {
        cacheDirectory()?.appending(path: file)
    }

    public static func cacheAge(file: String, now: Date = Date()) -> TimeInterval? {
        guard let url = cacheURL(file: file),
              let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
              .contentModificationDate else { return nil }
        return now.timeIntervalSince(modified)
    }

    // MARK: - Loading

    /// Every board jobhunt can sweep, refreshing any file older than `refreshInterval`.
    ///
    /// A file that can't be refreshed falls back to the cached copy however old it is: a stale
    /// directory sweeps a few boards that have since closed and misses a few that have opened,
    /// which is enormously better than sweeping nothing because GitHub was briefly unreachable.
    /// The board list, plus the vendors that could only be served from a stale or missing cache.
    ///
    /// `degraded` is returned rather than logged because a vendor silently dropping out of every
    /// sweep is exactly the failure this feature cannot afford, and the caller is the only thing
    /// that can tell the user.
    public static func boards(
        session: URLSession = .shared, now: Date = Date(), forceRefresh: Bool = false
    ) async -> (boards: [MarketBoard], degraded: [String]) {
        var all: [MarketBoard] = []
        var degraded: [String] = []
        for (kind, file) in files {
            guard let loaded = await load(
                file: file, kind: kind, session: session, now: now, forceRefresh: forceRefresh
            ) else {
                degraded.append(kind)
                continue
            }
            if loaded.degraded {
                degraded.append(kind)
            }
            all.append(contentsOf: decode(loaded.data, kind: kind))
        }
        return (all, degraded)
    }

    /// Fetch or reuse one dataset file, **validating before it is allowed to replace the cache**.
    ///
    /// A 200 is not proof of a usable file. A malformed upstream commit or a truncated response
    /// would otherwise overwrite the last known good copy with something that decodes to zero
    /// boards — silently removing an entire vendor from every sweep, and counting as fresh for a
    /// week. So the response has to parse into at least one board before it is written, and a
    /// response that doesn't falls back to whatever is already cached.
    static func load(
        file: String, kind: String, session: URLSession, now: Date, forceRefresh: Bool
    ) async -> (data: Data, degraded: Bool)? {
        let cached = cacheURL(file: file).flatMap { try? Data(contentsOf: $0) }
        let age = cacheAge(file: file, now: now)
        let fresh = !forceRefresh && age.map { $0 < refreshInterval } == true
        if fresh, let cached {
            return (cached, false)
        }

        func fallback() -> (Data, Bool)? {
            guard let cached else { return nil }
            // Reusing a stale copy sweeps a few boards that have closed and misses a few that have
            // opened. Sweeping nothing misses everything.
            return (cached, true)
        }

        guard let url = URL(string: "\(base)/\(file)") else { return fallback() }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("jobhunt", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty
        else { return fallback() }

        // The validation that makes the write safe.
        guard !decode(data, kind: kind).isEmpty else { return fallback() }

        if let target = cacheURL(file: file), let directory = cacheDirectory() {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try? data.write(to: target, options: .atomic)
        }
        return (data, false)
    }
}
