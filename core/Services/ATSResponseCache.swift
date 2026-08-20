import Foundation

/// Short-lived cache for ATS board responses, with coalescing of identical concurrent requests.
///
/// **Why this exists: the same check was giving different answers on consecutive runs.** A sweep over
/// a few hundred archived jobs asks the employer's ATS whether each posting is still listed, and that
/// answer is authoritative in both directions — a Greenhouse or Ashby posting can return HTTP 200
/// from a JavaScript shell while its board API says the posting is gone. But an ATS answer is only
/// used when it is *definitive*: a 429, a 5xx or a timeout means "don't know", and the job then falls
/// back to page heuristics that (correctly) refuse to judge a client-rendered shell. So a throttled
/// board call silently moves a job out of "gone" and into "couldn't verify" — the gone list shrinks,
/// with nothing to explain why.
///
/// Two properties fix that:
///
/// - **Coalescing.** Ten checks run concurrently and many share a board (73 Greenhouse postings
///   across 59 boards, 59 Ashby across 45 orgs), so the same board was fetched repeatedly, competing
///   with itself for the same rate limit.
/// - **A short TTL.** Re-running a check a few minutes later now replays the same board answers
///   instead of re-asking, so a second run gives the same result rather than a differently-throttled
///   one.
///
/// **Only definitive responses are cached.** A timeout, a refused connection, a 429 or a 5xx is never
/// stored — caching "don't know" would turn one unlucky moment into ten minutes of unlucky moments.
public actor ATSResponseCache {
    public static let shared = ATSResponseCache()

    /// Long enough to cover a sweep and an immediate re-run, short enough that a posting taken down
    /// this morning isn't reported live this afternoon.
    static let ttl: TimeInterval = 600

    public struct Response: Sendable {
        public let statusCode: Int
        public let body: Data
    }

    private struct Entry {
        let response: Response
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Response?, Never>] = [:]

    /// Fetch `request`, sharing the result with any concurrent caller asking for the same URL and
    /// replaying a recent definitive answer instead of re-asking.
    public func response(
        for request: URLRequest,
        session: URLSession,
        now: Date = Date()
    ) async -> Response? {
        guard let key = request.url?.absoluteString else { return nil }

        if let entry = entries[key], now.timeIntervalSince(entry.storedAt) < Self.ttl {
            return entry.response
        }
        if let running = inFlight[key] {
            return await running.value
        }

        let task = Task<Response?, Never> { [session] in
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else { return nil }
            return Response(statusCode: http.statusCode, body: data)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        // A 429/5xx is the ATS declining to answer, not an answer. Storing it would make one throttled
        // moment persist for the whole TTL — the opposite of what this cache is for.
        if let result, Self.isDefinitive(result.statusCode) {
            entries[key] = Entry(response: result, storedAt: now)
        }
        return result
    }

    /// 2xx and 404 are answers; everything else is the server declining to give one.
    static func isDefinitive(_ statusCode: Int) -> Bool {
        (200 ... 299).contains(statusCode) || statusCode == 404
    }

    /// Test hook — a process-wide cache would otherwise leak answers between test cases.
    public func reset() {
        entries.removeAll()
        inFlight.removeAll()
    }
}
