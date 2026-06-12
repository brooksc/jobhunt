import XCTest
@testable import JobhuntCore

final class ConsentHelperTests: XCTestCase {

    // MARK: - isLoopbackURL

    func testLoopback_localhost_isTrue() {
        XCTAssertTrue(ConsentHelper.isLoopbackURL("http://localhost:1234"))
    }

    func testLoopback_localhost_noPort_isTrue() {
        XCTAssertTrue(ConsentHelper.isLoopbackURL("http://localhost"))
    }

    func testLoopback_127_0_0_1_isTrue() {
        XCTAssertTrue(ConsentHelper.isLoopbackURL("http://127.0.0.1:8080"))
    }

    func testLoopback_127_other_octets_isTrue() {
        XCTAssertTrue(ConsentHelper.isLoopbackURL("http://127.1.2.3"))
        XCTAssertTrue(ConsentHelper.isLoopbackURL("http://127.255.255.255"))
    }

    func testLoopback_ipv6_localhost_isTrue() {
        XCTAssertTrue(ConsentHelper.isLoopbackURL("http://[::1]:8080"))
        XCTAssertTrue(ConsentHelper.isLoopbackURL("http://[::1]"))
    }

    func testLoopback_notlocalhost_isFalse() {
        XCTAssertFalse(ConsentHelper.isLoopbackURL("http://notlocalhost.evil.com"))
    }

    func testLoopback_subdomain_of_127_isFalse() {
        XCTAssertFalse(ConsentHelper.isLoopbackURL("http://evil-127.0.0.1.attacker.com"))
    }

    func testLoopback_0_0_0_0_isFalse() {
        XCTAssertFalse(ConsentHelper.isLoopbackURL("http://0.0.0.0:8080"))
    }

    func testLoopback_malformed_isFalse() {
        XCTAssertFalse(ConsentHelper.isLoopbackURL("not a url at all ☃"))
        XCTAssertFalse(ConsentHelper.isLoopbackURL(""))
    }

    func testLoopback_externalHost_isFalse() {
        XCTAssertFalse(ConsentHelper.isLoopbackURL("https://api.openai.com"))
        XCTAssertFalse(ConsentHelper.isLoopbackURL("https://api.anthropic.com"))
    }
}
