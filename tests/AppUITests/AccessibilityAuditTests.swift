import XCTest

/// Runs XCTest's own accessibility audit over the main screens (TASK-570 #5).
///
/// The audit reports what VoiceOver, Full Keyboard Access and the accessibility inspector would
/// complain about: controls with no description, insufficient contrast, elements the system can't
/// detect or act on. None of that shows up in a screenshot, which is why the rest of the UI suite
/// can't catch it.
///
/// **A ratchet, not a pass/fail gate.** The first run found ~190 issues, mostly contrast on
/// system-tinted chips and undescribed decorative elements. Gating on zero would mean either fixing
/// all of them in this task or disabling the audit within a week — the same trap `.warning-baseline`
/// exists to avoid for compiler warnings. So each screen has a recorded ceiling: new issues fail,
/// existing ones are a known debt (TASK-689), and lowering a ceiling is a deliberate commit.
///
/// The ceilings carry headroom because the audit walks whatever the demo seed produced, and a row
/// count that shifts moves the contrast tally with it. They're set to catch a screenful of new
/// problems, not a single extra chip.
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        app = launchApp()
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    /// Screen → the most issues it may report. Observed counts on 2026-08-22 were
    /// Dashboard 28, All Jobs 30, Needs Action 13, Sites 21, Data Quality 100.
    private let ceilings = [
        "Dashboard": 40,
        "All Jobs": 45,
        "Needs Action": 25,
        "Sites": 35,
        "Data Quality": 130
    ]

    func testMainScreensStayWithinTheirAccessibilityDebt() throws {
        for (screen, ceiling) in ceilings.sorted(by: { $0.key < $1.key }) {
            navigate(app, label: screen)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

            var issues: [String] = []
            // The handler returning true means "reported, don't fail the test" — this counts rather
            // than throwing on the first finding.
            try app.performAccessibilityAudit { issue in
                issues.append(issue.compactDescription)
                return true
            }

            XCTContext.runActivity(named: "Audit: \(screen) — \(issues.count) issues") { activity in
                let report = XCTAttachment(string: issues.joined(separator: "\n"))
                report.name = "accessibility-\(screen).txt"
                report.lifetime = .keepAlways
                activity.add(report)
            }
            XCTAssertLessThanOrEqual(
                issues.count, ceiling,
                """
                \(screen) reports \(issues.count) accessibility issues, above its recorded \
                ceiling of \(ceiling). See the attachment for what they are. Fix the new ones \
                rather than raising the number.
                """
            )
        }
    }
}
