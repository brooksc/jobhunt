import XCTest

/// Exercises the referral outreach editor across several iterations on the isolated demo store
/// (`--ui-test-store` never touches real or demo-production data). Guards the regressions chased in the
/// TASK-644 review: the editor's text field must accept input, its inline date field must expand
/// without crashing (the popover-in-sheet crash), and repeated open→enter→save cycles must neither
/// silently corrupt input nor crash the app (the intermittent "3rd time" failure).
final class ReferralUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    @MainActor
    func testReferralEditor_repeatedOpenTypeDateSave_staysResponsiveAndDoesNotCrash() {
        app.typeKey("k", modifierFlags: .command) // reliable jump to All Jobs

        let jobsOutline = app.descendants(matching: .any).matching(identifier: "content.jobs").firstMatch
        XCTAssertTrue(jobsOutline.waitForExistence(timeout: 15), "Jobs list (content.jobs) must exist")

        // Select a job whose detail offers the referral section (Interested/Applied in the seed data).
        let addOutreach = app.buttons["referral.addOutreach"]
        let cells = jobsOutline.descendants(matching: .cell)
        var opened = false
        for index in 0 ..< max(1, min(cells.count, 10)) {
            let cell = cells.element(boundBy: index)
            guard cell.waitForExistence(timeout: 3) else { continue }
            cell.click()
            if addOutreach.waitForExistence(timeout: 3) { opened = true; break }
        }
        XCTAssertTrue(opened, "Expected at least one seeded job to show the referral section")
        scrollToHittable(addOutreach)

        let recipient = app.textFields["referral.recipient"]
        let save = app.buttons["referral.save"]
        let requestedDate = app.buttons["dateField.Requested"]

        for iteration in 1 ... 6 {
            // 1. Open the editor.
            XCTAssertTrue(addOutreach.waitForExistence(timeout: 5), "iter \(iteration): Add outreach missing")
            scrollToHittable(addOutreach)
            addOutreach.click()

            // 2. Text input must actually register (the responder bug made it silently dead).
            XCTAssertTrue(recipient.waitForExistence(timeout: 5), "iter \(iteration): recipient field missing")
            recipient.click()
            let name = "Tester \(iteration)"
            recipient.typeText(name)
            XCTAssertEqual(recipient.value as? String, name, "iter \(iteration): recipient input didn't register")

            // 3. The inline date field must expand — and must NOT crash (the popover-in-sheet bug).
            XCTAssertTrue(requestedDate.waitForExistence(timeout: 5), "iter \(iteration): date field missing")
            requestedDate.click()
            XCTAssertEqual(app.state, .runningForeground, "iter \(iteration): app crashed opening the date field")
            XCTAssertTrue(
                app.datePickers.firstMatch.waitForExistence(timeout: 5),
                "iter \(iteration): inline calendar didn't appear"
            )
            requestedDate.click() // collapse

            // 4. Save and confirm the editor dismissed.
            save.click()
            XCTAssertTrue(
                waitForDisappearance(recipient, timeout: 5),
                "iter \(iteration): editor didn't dismiss after Save"
            )

            // 5. The app must still be alive after every cycle.
            XCTAssertEqual(app.state, .runningForeground, "iter \(iteration): app is no longer running (crash?)")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)],
            timeout: timeout
        ) == .completed
    }

    /// Scroll the window down until `element` is hittable (the referral section can sit below the fold).
    @MainActor
    private func scrollToHittable(_ element: XCUIElement, attempts: Int = 6) {
        var tries = 0
        while element.exists, !element.isHittable, tries < attempts {
            app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: -160)
            Thread.sleep(forTimeInterval: 0.3)
            tries += 1
        }
    }
}
