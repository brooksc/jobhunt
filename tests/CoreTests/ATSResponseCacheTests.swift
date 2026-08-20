import Foundation
import XCTest
@testable import JobhuntCore

/// The same archive check reported 7 gone jobs, then 4, over an unchanged set of jobs. An ATS answer
/// is only used when it is definitive, so a throttled board call doesn't merely fail — it demotes the
/// job from "gone" to "couldn't verify" and it silently leaves the list. Caching and coalescing the
/// board calls removes most of that throttling; caching the *wrong* things would make it permanent.
final class ATSResponseCacheTests: XCTestCase {
    private var session: URLSession!

    override func setUp() async throws {
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
    }

    private func request(_ url: String) -> URLRequest {
        URLRequest(url: URL(string: url)!)
    }

    private func stub(_ pattern: String, status: Int, body: String = "{}", counter: Counter) {
        MockURLProtocol.handlers.append((pattern, { request in
            counter.bump()
            return (
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }))
    }

    /// Mutable request counter usable from the protocol's synchronous handler.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() {
            lock.lock(); value += 1; lock.unlock()
        }

        var count: Int {
            lock.lock(); defer { lock.unlock() }; return value
        }
    }

    /// A definitive answer is replayed rather than re-asked — this is what makes an immediate re-run
    /// agree with the run before it.
    func testDefinitiveAnswerIsCached() async {
        let counter = Counter()
        stub("/board-a", status: 200, counter: counter)

        let first = await ATSResponseCache.shared.response(for: request("https://ats.test/board-a"), session: session)
        let second = await ATSResponseCache.shared.response(for: request("https://ats.test/board-a"), session: session)

        XCTAssertEqual(first?.statusCode, 200)
        XCTAssertEqual(second?.statusCode, 200)
        XCTAssertEqual(counter.count, 1, "the second ask must be served from the cache")
    }

    /// A 404 is an answer too — "this posting is gone" is exactly the verdict worth keeping stable.
    func testNotFoundIsCached() async {
        let counter = Counter()
        stub("/board-404", status: 404, counter: counter)

        _ = await ATSResponseCache.shared.response(for: request("https://ats.test/board-404"), session: session)
        let second = await ATSResponseCache.shared.response(
            for: request("https://ats.test/board-404"),
            session: session
        )

        XCTAssertEqual(second?.statusCode, 404)
        XCTAssertEqual(counter.count, 1)
    }

    /// A throttle or a server error is the ATS declining to answer. Caching it would turn one unlucky
    /// moment into ten minutes of them — the opposite of the point.
    func testTransientFailuresAreNotCached() async {
        for status in [429, 500, 503] {
            MockURLProtocol.reset()
            let counter = Counter()
            stub("/flaky-\(status)", status: status, counter: counter)

            _ = await ATSResponseCache.shared.response(
                for: request("https://ats.test/flaky-\(status)"), session: session
            )
            _ = await ATSResponseCache.shared.response(
                for: request("https://ats.test/flaky-\(status)"), session: session
            )
            XCTAssertEqual(counter.count, 2, "HTTP \(status) must be retried, never replayed")
        }
    }

    /// The classification the caching rule rests on.
    func testDefinitiveClassification() {
        XCTAssertTrue(ATSResponseCache.isDefinitive(200))
        XCTAssertTrue(ATSResponseCache.isDefinitive(204))
        XCTAssertTrue(ATSResponseCache.isDefinitive(404))
        for status in [301, 429, 500, 502, 503] {
            XCTAssertFalse(ATSResponseCache.isDefinitive(status), "HTTP \(status) is not an answer")
        }
    }

    /// Ten checks run concurrently and many share a board, so identical in-flight requests must
    /// collapse into one — they were previously competing with each other for the same rate limit.
    func testConcurrentRequestsForTheSameURLCoalesce() async {
        let counter = Counter()
        stub("/busy-board", status: 200, counter: counter)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 10 {
                group.addTask { [session] in
                    _ = await ATSResponseCache.shared.response(
                        for: URLRequest(url: URL(string: "https://ats.test/busy-board")!),
                        session: session!
                    )
                }
            }
        }
        XCTAssertEqual(counter.count, 1, "one board, one request")
    }

    /// An expired entry is re-fetched: a posting pulled this morning must not read as live all day.
    func testEntriesExpire() async {
        let counter = Counter()
        stub("/aging-board", status: 200, counter: counter)
        let start = Date()

        _ = await ATSResponseCache.shared.response(
            for: request("https://ats.test/aging-board"), session: session, now: start
        )
        _ = await ATSResponseCache.shared.response(
            for: request("https://ats.test/aging-board"), session: session,
            now: start.addingTimeInterval(ATSResponseCache.ttl + 1)
        )
        XCTAssertEqual(counter.count, 2)
    }
}
