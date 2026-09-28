import XCTest

@MainActor
final class AttendanceSummaryUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The shared fake with birthdays by default. Pass the legacy fake's flags
    /// (for example `["-ui-offline"]`) to drop the shared one.
    private func launch(largeText: Bool = false, fixture: [String] = ["-ui-shared-guests", "-ui-birthdays"]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + fixture
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
    }

    /// Birthdays live on the Events tab (R22). Every launch starts on Runs.
    private func openEvents() {
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
        app.tab(.events).tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))
    }

    private func tap(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        element.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCountIncludesChecksAndGuestsAndSurvivesSearch() {
        launch()
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-42"])
        let count = app.staticTexts["attendance-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "1 checked")
        XCTAssertEqual(app.staticTexts["attendance-total"].label, "3 people including 2 guests")
        tap(app.buttons["member-Aaron"])
        XCTAssertEqual(count.label, "2 checked")
        XCTAssertEqual(app.staticTexts["attendance-total"].label, "4 people including 2 guests")
        capture("attendance-count")

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Aaron")
        XCTAssertEqual(count.label, "2 checked")
        tap(app.buttons["member-Aaron"])
        XCTAssertEqual(count.label, "1 checked")
        XCTAssertEqual(app.staticTexts["attendance-total"].label, "3 people including 2 guests")
    }

    func testBirthdaysAppearBelowUnchangedMilestones() {
        launch()
        openEvents()
        let birthday = app.descendants(matching: .any)["birthday-row-Aaron"].firstMatch
        let nextBirthday = app.descendants(matching: .any)["birthday-row-Col"].firstMatch
        for _ in 0..<5 {
            if nextBirthday.exists && nextBirthday.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(birthday.exists)
        XCTAssertTrue(birthday.label.contains("Today"), birthday.label)
        XCTAssertTrue(nextBirthday.exists)
        XCTAssertFalse(app.descendants(matching: .any)["birthday-row-Dan"].firstMatch.exists)
        capture("upcoming-birthdays")
    }

    func testGuestChangesUpdateHeadCountWithoutChangingTicks() {
        launch()
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-42"])
        tap(app.buttons["guest-editor"])
        let stepper = app.steppers["unnamed-guests"]
        stepper.buttons.matching(NSPredicate(format: "label CONTAINS 'Increment'")).firstMatch.tap()
        XCTAssertEqual(stepper.value as? String, "2")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.staticTexts["attendance-count"].label, "1 checked")
        XCTAssertEqual(app.staticTexts["attendance-total"].label, "4 people including 3 guests")
        tap(app.buttons["member-Col"])
        tap(app.buttons["guest-editor"])
        for _ in 0..<2 {
            stepper.buttons.matching(NSPredicate(format: "label CONTAINS 'Decrement'")).firstMatch.tap()
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.staticTexts["attendance-count"].label, "0 checked")
        XCTAssertEqual(app.staticTexts["attendance-total"].label, "1 person including 1 guest")
    }

    func testEmptyBirthdaysAndOlderServerRemainUsable() {
        launch()
        app.terminate()
        app.launchArguments += ["-ui-no-birthdays"]
        app.launch()
        openEvents()
        let empty = app.staticTexts["birthday-empty"]
        for _ in 0..<5 {
            if empty.exists && empty.isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(empty.label, "No birthdays in the next 30 days.")
        capture("birthdays-empty")

        app.terminate()
        app.launchArguments = ["-ui-testing", "-ui-shared-guests"]
        app.launch()
        openEvents()
        for _ in 0..<5 {
            if empty.exists && empty.isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(empty.label, "Birthdays are not available yet.")
    }

    func testBirthdaysRemainAvailableAfterOfflineRelaunch() {
        launch()
        let store = UUID().uuidString
        app.terminate()
        app.launchArguments += ["-ui-store-name", store]
        app.launch()
        openEvents()
        let birthday = app.descendants(matching: .any)["birthday-row-Aaron"].firstMatch
        for _ in 0..<5 {
            if birthday.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(birthday.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["-ui-state-offline"]
        app.launch()
        openEvents()
        for _ in 0..<5 {
            if birthday.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(birthday.waitForExistence(timeout: 5))
        XCTAssertTrue(birthday.label.contains("Today"))
    }

    func testLargeTextSummaryAndBirthdays() {
        launch(largeText: true)
        openEvents()
        let birthday = app.descendants(matching: .any)["birthday-row-Aaron"].firstMatch
        for _ in 0..<8 {
            if birthday.exists && birthday.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(birthday.exists)
        capture("birthdays-large-text")
        app.terminate()
        launch(largeText: true)
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-42"])
        let count = app.staticTexts["attendance-count"]
        for _ in 0..<8 {
            if count.exists && count.isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(count.label, "1 checked")
        XCTAssertTrue(app.staticTexts["attendance-total"].exists)
        // A header can be hittable behind the bottom search glass. Bring the full
        // summary and first member into the viewport for visual review.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        capture("attendance-large-text")
    }

    // MARK: Events tab (R22, R26)

    /// Any element by identifier: combined rows and section headers are not
    /// always the element type their content suggests.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func elements(prefixed prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    func testEventsListsTheWeekSpecialsMilestonesAndBirthdays() {
        launch(fixture: ["-ui-shared-guests", "-ui-birthdays", "-ui-events"])
        openEvents()
        XCTAssertTrue(element("events-this-week").waitForExistence(timeout: 5))

        // `-ui-events` pins today to Monday 21 Sep 2026 (`UITestSupport.now`),
        // so the week is the same every day the suite runs: today's row 42,
        // then the fixture's Wednesday and Friday plans. Sunday is no club day.
        let week = elements(prefixed: "week-row-")
        XCTAssertEqual(week.count, 3)
        XCTAssertFalse(element("week-empty").exists)
        let expected = [("Soft Sand", "Il Lido · 7.1 km"), ("Lakes Loop", "Filament · 12.5 km"), ("Soft Sand", "Il Lido · 7 km")]
        for (index, (title, detail)) in expected.enumerated() {
            let label = week.element(boundBy: index).label
            XCTAssertTrue(label.contains(title) && label.contains(detail), label)
        }
        capture("events-top")

        // The three Christmas races share a date, so they are one row.
        let xmasRows = elements(prefixed: "special-row-").matching(NSPredicate(format: "label CONTAINS 'Xmas'"))
        let xmas = xmasRows.firstMatch
        scrollTo(xmas)
        XCTAssertTrue(xmas.exists)
        XCTAssertTrue(xmas.label.contains("Mara / Half / 10k"), xmas.label)
        XCTAssertEqual(xmasRows.count, 1)

        let aaron = element("milestone-row-Aaron")
        scrollTo(aaron)
        XCTAssertTrue(aaron.label.contains("3 runs to 150"), aaron.label)
        XCTAssertTrue(aaron.label.contains("147 all-time runs"), aaron.label)

        let birthday = element("birthday-row-Aaron")
        scrollTo(birthday)
        XCTAssertTrue(birthday.label.contains("Today"), birthday.label)
        capture("events-bottom")
    }

    func testEventsMilestonesCountAnUnsyncedRun() {
        // The legacy fake, never draining: the recorded run waits in the outbox.
        launch(fixture: ["-ui-offline"])
        openEvents()
        let aaron = element("milestone-row-Aaron")
        XCTAssertTrue(aaron.waitForExistence(timeout: 5))
        XCTAssertTrue(aaron.label.contains("3 runs to 150"), aaron.label)

        app.tab(.runs).tap()
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-43"])
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 3))
        tap(app.buttons["member-Aaron"])
        app.buttons["confirm-attendance"].tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-unsynced"].label.contains("1 submissions"), app.buttons["home-unsynced"].label)

        openEvents()
        let updated = element("milestone-row-Aaron")
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        XCTAssertTrue(updated.label.contains("2 runs to 150"), updated.label)
    }

    func testEventsSaysWhenNothingIsAhead() {
        // The legacy fake's two runs are both in the past.
        launch(fixture: [])
        openEvents()
        let week = element("week-empty")
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertEqual(week.label, "No more runs this week.")
        XCTAssertEqual(element("specials-empty").label, "No specials scheduled.")
    }
}
