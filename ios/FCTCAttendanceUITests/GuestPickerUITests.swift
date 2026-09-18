import XCTest

@MainActor
final class GuestPickerUITests: XCTestCase {
    private var app: XCUIApplication!

    private func openGuests(row: Int, largeText: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-shared-guests"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-\(row)"])
        tap(app.buttons["guest-editor"])
    }

    private func tap(_ element: XCUIElement) {
        for _ in 0..<7 {
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

    private func assertKeyboardDismissed() {
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [hidden], timeout: 5)
    }

    func testNamePickerCanCancelOrUseSavedGuestWithoutAddingAttendance() {
        openGuests(row: 42)
        tap(app.buttons["name-unnamed-guest"])
        XCTAssertTrue(app.navigationBars["Name a guest"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["guest-picker-name"].exists)
        XCTAssertTrue(app.buttons["guest-picker-select-Toby"].isHittable)
        XCTAssertFalse(app.buttons["guest-picker-select-Rene"].exists)
        capture("guest-picker-saved-choices")

        tap(app.buttons["guest-picker-cancel"])
        XCTAssertEqual(app.steppers["unnamed-guests"].value as? String, "1")
        XCTAssertTrue(app.staticTexts["selected-guest-Rene"].exists)
        XCTAssertFalse(app.staticTexts["selected-guest-Toby"].exists)

        tap(app.buttons["name-unnamed-guest"])
        tap(app.buttons["guest-picker-select-Toby"])
        XCTAssertTrue(app.staticTexts["selected-guest-Toby"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["selected-guest-Rene"].exists)
        XCTAssertEqual(app.steppers["unnamed-guests"].value as? String, "0")
        XCTAssertFalse(app.buttons["guest-picker-cancel"].exists)
        XCTAssertFalse(app.buttons["Cancel selection"].exists)
        capture("guest-picker-saved-name-selected")
    }

    func testNewNameUsesOneOfThreeGuestsAddedOnThisRun() {
        openGuests(row: 43)
        let stepper = app.steppers["unnamed-guests"]
        for _ in 0..<3 { stepper.buttons.matching(NSPredicate(format: "label CONTAINS 'Increment'")).firstMatch.tap() }
        XCTAssertEqual(stepper.value as? String, "3")
        tap(app.buttons["name-unnamed-guest"])
        let field = app.textFields["guest-picker-name"]
        field.tap()
        field.typeText("Adam X")
        tap(app.buttons["guest-picker-keyboard-done"])
        assertKeyboardDismissed()
        capture("guest-picker-new-name")
        tap(app.buttons["guest-picker-create"])

        XCTAssertTrue(app.staticTexts["selected-guest-Adam X"].waitForExistence(timeout: 8))
        XCTAssertEqual(stepper.value as? String, "2")
        XCTAssertFalse(app.buttons["guest-picker-cancel"].exists)
        capture("guest-picker-same-run-name-selected")
    }

    func testReplacePickerChangesPersonAndKeepsUnnamedCount() {
        openGuests(row: 42)
        let rene = app.staticTexts["selected-guest-Rene"]
        XCTAssertTrue(rene.waitForExistence(timeout: 5))
        app.cells.containing(.staticText, identifier: "selected-guest-Rene").firstMatch.swipeLeft()
        tap(app.buttons["Replace"])
        XCTAssertTrue(app.navigationBars["Replace guest"].waitForExistence(timeout: 5))
        capture("guest-picker-replace-choice")
        tap(app.buttons["guest-picker-select-Toby"])
        XCTAssertTrue(app.staticTexts["selected-guest-Toby"].waitForExistence(timeout: 5))
        XCTAssertFalse(rene.exists)
        XCTAssertEqual(app.steppers["unnamed-guests"].value as? String, "1")
    }

    func testGuestSearchKeyboardDismissesWithDoneAndDrag() {
        openGuests(row: 42)
        let field = app.textFields["add-guest-field"]
        tap(field)
        field.typeText("T")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["guest-keyboard-done"])
        assertKeyboardDismissed()

        tap(field)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Start inside the list, above the keyboard toolbar. Scrolling in either
        // direction should dismiss the keyboard without requiring Return.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.keyboards.firstMatch.frame.minY - 110))
        let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.minY + 150))
        start.press(forDuration: 0.05, thenDragTo: end)
        assertKeyboardDismissed()
        capture("guest-picker-keyboard-dismissed")
    }

    func testNamePickerSupportsLargestDynamicType() {
        openGuests(row: 42, largeText: true)
        tap(app.buttons["name-unnamed-guest"])
        XCTAssertTrue(app.navigationBars["Name a guest"].waitForExistence(timeout: 5))
        capture("guest-picker-large-text")
        tap(app.buttons["guest-picker-select-Toby"])
        XCTAssertTrue(app.staticTexts["selected-guest-Toby"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.steppers["unnamed-guests"].value as? String, "0")
    }
}
