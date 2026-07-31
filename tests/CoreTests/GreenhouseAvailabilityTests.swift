import Foundation
import XCTest
@testable import JobhuntCore

/// Job #341 (Nebius) stayed listed as available after the posting was pulled. Its career page —
/// `careers.nebius.com/?gh_jid=…` — is a JavaScript shell that returns HTTP 200 with no removal
/// wording whether or not the job exists, so every page heuristic reads "available". The Greenhouse
/// API answered `404 Job not found` the whole time, but that was only ever consulted to VETO a
/// would-be-gone result, never to produce one.
final class GreenhouseAvailabilityTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        MockURLProtocol.handlers = []
    }

    override func tearDown() {
        MockURLProtocol.handlers = []
        super.tearDown()
    }

    private func availability(company: String? = "Nebius", ghjid: String = "4817337101") async -> Bool? {
        await AvailabilityChecker.greenhouseAvailability(
            ghjid: ghjid, company: company,
            urlString: "https://careers.nebius.com/?gh_jid=\(ghjid)", session: session
        )
    }

    private func response(_ url: String, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - The reported failure

    /// A removed posting on a board that resolves is definitively gone.
    func testJob404OnARealBoardMeansRemoved() async {
        MockURLProtocol.handlers = [
            ("/jobs/4817337101", { _ in
                (self.response("https://boards-api.greenhouse.io/x", 404), Data("{}".utf8))
            }),
            ("/v1/boards/nebius", { _ in
                (self.response("https://boards-api.greenhouse.io/y", 200), Data("{}".utf8))
            })
        ]
        let result = await availability()
        XCTAssertEqual(result, false, "the API's 404 is the authoritative answer")
    }

    func testLivePostingIsReportedAlive() async {
        MockURLProtocol.handlers = [("/jobs/", { _ in
            (self.response("https://boards-api.greenhouse.io/x", 200), Data(#"{"id":1}"#.utf8))
        })]
        let result = await availability()
        XCTAssertEqual(result, true)
    }

    // MARK: - The guard against mass false-expiry

    /// The board slug is guessed from the company name. If the guess is wrong, EVERY posting on it
    /// 404s — which without this guard would expire a whole board of live jobs.
    func testJob404OnAnUnresolvableBoardIsNotTreatedAsRemoved() async {
        MockURLProtocol.handlers = [("boards-api.greenhouse.io", { _ in
            (self.response("https://boards-api.greenhouse.io/x", 404), Data("{}".utf8))
        })]
        let result = await availability(company: "Totally Wrong Name")
        XCTAssertNil(result, "an unresolvable board must yield 'unknown', never 'gone'")
    }

    /// Rate limiting and server faults are not evidence of removal.
    func testTransientFailuresYieldUnknown() async {
        for status in [429, 500, 503] {
            MockURLProtocol.handlers = [("boards-api.greenhouse.io", { _ in
                (self.response("https://boards-api.greenhouse.io/x", status), Data("{}".utf8))
            })]
            let result = await availability()
            XCTAssertNil(result, "HTTP \(status) must not read as removed")
        }
    }

    /// A live posting must win even when an earlier candidate board 404s, so the multi-candidate
    /// search can't turn a good job into a removed one.
    func testALiveHitOnALaterCandidateWins() async {
        MockURLProtocol.handlers = [
            ("/v1/boards/nebius/jobs/", { _ in
                (self.response("https://boards-api.greenhouse.io/x", 200), Data(#"{"id":1}"#.utf8))
            }),
            ("boards-api.greenhouse.io", { _ in
                (self.response("https://boards-api.greenhouse.io/y", 404), Data("{}".utf8))
            })
        ]
        let result = await availability()
        XCTAssertEqual(result, true)
    }
}
