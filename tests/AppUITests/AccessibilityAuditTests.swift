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

    /// Screen → the most issues it may report. Observed on 2026-08-22 after the first pass of
    /// TASK-689: Dashboard 28, All Jobs 30, Needs Action 12, Sites 19, Data Quality 64.
    ///
    /// What's left is mostly not ours to fix by a code change alone. The bulk is macOS's own
    /// `.secondary`/`.tertiary` label colours at 13–16pt, which the audit measures below 4.5:1 —
    /// overriding Apple's semantic colours app-wide is a design decision, not a defect fix. The rest
    /// is SwiftUI exposing structural containers (the split view, the sidebar column) as unlabelled
    /// groups, and the Touch Bar simulator, which isn't our UI at all.
    private let ceilings = [
        "Dashboard": 38,
        "All Jobs": 40,
        "Needs Action": 20,
        "Sites": 28,
        "Data Quality": 80
    ]

    func testMainScreensStayWithinTheirAccessibilityDebt() throws {
        for (screen, ceiling) in ceilings.sorted(by: { $0.key < $1.key }) {
            navigate(app, label: screen)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

            var issues: [String] = []
            // The handler returning true means "reported, don't fail the test" — this counts rather
            // than throwing on the first finding.
            try app.performAccessibilityAudit { issue in
                // The element, not just the complaint: "Element has no description" on its own names
                // nothing to fix. `element` is the audit's own handle on the offending view.
                let element = issue.element
                    .map { "\($0.elementType.rawValue) id=\($0.identifier) label=\($0.label) frame=\($0.frame)" }
                issues.append("\(issue.compactDescription) | \(element ?? "no element")")
                return true
            }

            XCTContext.runActivity(named: "Audit: \(screen) — \(issues.count) issues") { activity in
                let report = XCTAttachment(string: issues.joined(separator: "\n"))
                report.name = "accessibility-\(screen).txt"
                report.lifetime = .keepAlways
                activity.add(report)
            }
            // Also to a known path: an attachment is only readable by opening the .xcresult, which
            // makes working the debt down (TASK-689) far more awkward than it needs to be. Same
            // reasoning as the screenshot directory above.
            try? issues.joined(separator: "\n").write(
                to: screenshotDir.appendingPathComponent("accessibility-\(screen).txt"),
                atomically: true, encoding: .utf8
            )
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
