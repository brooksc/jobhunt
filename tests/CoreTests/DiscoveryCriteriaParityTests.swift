import Foundation
import XCTest
@testable import JobhuntCore

/// Parity between gate A and the career-ops scanner it was ported from (TASK-691, M2).
///
/// `DiscoveryCriteria` reimplements filters that ran daily in a Node scanner for months. Unit tests
/// prove each rule does what its comment says; this proves the *whole* gate agrees with the
/// implementation whose behaviour is already known-good — which is a different and stronger claim,
/// because it catches a rule that is individually correct but composed in the wrong order.
///
/// **How the expectations were produced.** The verdicts below are not hand-written. Each case was
/// run through career-ops' own `buildTitleFilter` / `buildLocationFilter` (`scan.mjs`) with the
/// config in `criteria` below, and the result recorded verbatim on 2026-08-22. Swift and JS
/// disagreed on 0 of 32 adversarial cases, and separately on 0 of 204 real roles from a live
/// GitLab board.
///
/// The cases are deliberately adversarial rather than realistic: real board data almost never
/// contains "Indian Head, MD", which is exactly why the bug it represents survived in production
/// long enough to be worth a regression test.
///
/// A future change that intentionally diverges from career-ops should update the expectation and
/// say why in the commit — the point is that divergence has to be deliberate, not discovered.
final class DiscoveryCriteriaParityTests: XCTestCase {
    /// Synthesised, not a real user's configuration, but shaped to exercise every tier: an
    /// always-allow that must beat a block, a block_hard that must beat the always-allow, short
    /// acronyms that must anchor, and negatives that must veto.
    private let criteria = DiscoveryCriteria(
        titleIncludeAny: ["program manager", "product manager", "coo", "tpm", "chief of staff"],
        titleExcludeAny: ["intern", "junior", "associate"],
        locationBlockHard: ["brazil"],
        locationAlwaysAllow: ["remote, united states", "new mexico"],
        locationBlock: ["india", "mexico", "brazil", "emea", "germany", "london"],
        locationAllow: ["remote", "united states"]
    )

    /// title, location, whether career-ops passed it.
    private let cases: [(String, String, Bool)] = [
        // Word-boundary location matching: "india" must not match three real US places.
        ("Program Manager", "Indianapolis, IN", false),
        ("Program Manager", "Indian Head, MD", false),
        ("Program Manager", "Bengaluru, India", false),
        ("Program Manager", "Indiana, US", false),
        ("Program Manager", "Chinatown, San Francisco", false),
        // always_allow beats block ("new mexico" over "mexico")…
        ("Program Manager", "New Mexico", true),
        ("Program Manager", "Mexico City, Mexico", false),
        ("Program Manager", "Porto, Portugal", false),
        // …but block_hard beats always_allow.
        ("Program Manager", "Porto Alegre, Brazil", false),
        ("Program Manager", "Stockholm; London; Madrid", false),
        // Remote-title rescue, and the compounds and negations that must not trigger it.
        ("Program Manager - Remote", "Las Vegas, Nevada", true),
        ("Remote Sensing Program Manager", "Redlands, California", false),
        ("Program Manager - Non-Remote", "Berlin, Germany", false),
        ("Program Manager (Not Remote)", "Berlin, Germany", false),
        ("Nonprofit Program Manager - Remote", "Berlin, Germany", false),
        // Short-acronym anchoring: "coo" must not match Coordinator; "tpm" must match alone.
        ("Program Coordinator", "Remote, United States", false),
        ("COO", "Remote, United States", true),
        ("Chief of Staff", "Remote, US", true),
        ("TPM", "Remote, US", true),
        ("Senior TPM, Infra", "Remote, US", true),
        // "Remote in MO" is a remote marker; "5 Locations" is a rollup with nothing to match.
        ("Program Manager", "Remote in MO", true),
        ("Program Manager", "5 Locations", false),
        // Punctuation-edge keywords: "truck -" must not match a "uk -" style entry.
        ("Program Manager", "Truck - Depot", false),
        ("Program Manager", "UK - London", false),
        // Negative title keywords veto a matching positive.
        ("Product Management Intern", "Remote, US", false),
        ("Junior Product Manager", "Remote, US", false),
        ("Associate Program Manager", "Remote, United States", false),
        // Absent location passes; an allow keyword may match anywhere in the string.
        ("Program Manager", "Remote, Canada", true),
        ("Program Manager", "", true),
        ("Program Manager", "united states - remote", true),
        ("Program Manager", "EMEA", false),
        // "program management" is not "program manager" — substring matching is literal.
        ("Program Management Lead", "Remote - US", false)
    ]

    func testEveryCaseAgreesWithTheScannerItWasPortedFrom() {
        for (title, location, expected) in cases {
            let posting = DiscoveredPosting(
                dedupKey: "x", url: "https://example.com/1", title: title,
                locationRaw: location.isEmpty ? nil : location
            )
            let passed = criteria.evaluate(posting) == .pass
            XCTAssertEqual(
                passed, expected,
                "\(title) | \(location) — career-ops \(expected ? "passed" : "rejected") this"
            )
        }
    }
}
