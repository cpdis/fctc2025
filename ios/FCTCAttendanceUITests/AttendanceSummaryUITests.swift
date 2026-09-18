import XCTest

@MainActor
final class AttendanceSummaryUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(largeText: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-shared-guests", "-ui-birthdays"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
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
        let birthday = app.descendants(matching: .any)["birthday-row-Aaron"].firstMatch
        for _ in 0..<5 {
            if birthday.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(birthday.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["-ui-state-offline"]
        app.launch()
        for _ in 0..<5 {
            if birthday.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(birthday.waitForExistence(timeout: 5))
        XCTAssertTrue(birthday.label.contains("Today"))
    }

    func testLargeTextSummaryAndBirthdays() {
        launch(largeText: true)
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
}
