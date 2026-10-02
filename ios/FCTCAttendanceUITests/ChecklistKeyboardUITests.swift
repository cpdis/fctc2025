//
//  ChecklistKeyboardUITests.swift
//  FCTCAttendanceUITests
//
//  The decimal pad has no Return key. These tests guard the two exits the
//  distance fields rely on: the keyboard toolbar's Done button and a scroll.
//
//  These tests need the simulator's software keyboard: disconnect the hardware
//  keyboard (I/O > Keyboard > Connect Hardware Keyboard off), or no toolbar shows.
//

import XCTest

@MainActor
final class ChecklistKeyboardUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Gap above the keyboard that keeps a drag start clear of the Done toolbar.
    private let keyboardToolbarClearance: CGFloat = 110

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
        tap(app.buttons["home-all-runs"])
    }

    private func openChecklist(row: Int) {
        launch()
        tap(app.buttons["run-row-\(row)"])
        XCTAssertTrue(app.textFields["actual-km"].waitForExistence(timeout: 5))
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

    /// Focuses a distance field and replaces whatever the fixture seeded it with.
    /// The text is trailing-aligned, so the tap lands on its end: a centre tap
    /// would put the cursor in front of the text and the deletes would do nothing.
    private func replaceText(in field: XCUIElement, with text: String) {
        for _ in 0..<7 {
            if field.exists && field.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // `value` is the placeholder when the field is empty; extra deletes are harmless.
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        field.typeText(text)
    }

    /// Keyboard toolbar buttons are tapped without the swipe fallback: a swipe
    /// would dismiss the keyboard and take the button with it.
    private func tapKeyboardButton(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private func assertKeyboardDismissed() {
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [hidden], timeout: 5)
    }

    /// Drags upward from inside the list, above the keyboard toolbar, the way an
    /// organiser scrolls down to reach the rest of the roster.
    private func scrollListAboveKeyboard() {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.keyboards.firstMatch.frame.minY - keyboardToolbarClearance))
        let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.minY + 150))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func testActualKmDecimalPadDismissesWithDone() {
        openChecklist(row: 43)
        let field = app.textFields["actual-km"]
        replaceText(in: field, with: "9.5")
        tapKeyboardButton("actual-km-keyboard-done")
        assertKeyboardDismissed()
        XCTAssertEqual(field.value as? String, "9.5")
        XCTAssertTrue(app.buttons["confirm-attendance"].isEnabled)
    }

    func testActualKmKeyboardDismissesOnScrollAndKeepsValue() {
        openChecklist(row: 43)
        let field = app.textFields["actual-km"]
        replaceText(in: field, with: "9.5")
        scrollListAboveKeyboard()
        assertKeyboardDismissed()
        XCTAssertEqual(field.value as? String, "9.5")
    }

    /// The Done button belongs to the distance field alone. The search field and
    /// the quick-add row have their own Return key.
    func testSearchKeyboardHasNoDistanceDoneButton() {
        openChecklist(row: 43)
        let search = app.searchFields.firstMatch
        tap(search)
        search.typeText("Aa")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["actual-km-keyboard-done"].exists)
        XCTAssertTrue(app.buttons["member-Aaron"].waitForExistence(timeout: 5))
    }

    /// Aaron's report: the distance is typed, the keyboard is still up, and the
    /// organiser taps Confirm in the navigation bar. The typed value must reach
    /// the sheet without Done or a scroll first.
    func testTypedDistanceSurvivesConfirmWithKeyboardUp() {
        openChecklist(row: 43)
        replaceText(in: app.textFields["actual-km"], with: "9.5")
        // Tap Confirm directly: the swipe fallback would dismiss the keyboard first.
        let confirm = app.buttons["confirm-attendance"]
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()

        // Confirming pops to Home and queues the write. Wait for the automatic
        // drain to land it in the fake sheet, then reopen the run and read it back.
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        let drained = expectation(
            for: NSPredicate(format: "label == 'Unsynced, 0 submissions'"),
            evaluatedWith: app.buttons["home-unsynced"]
        )
        wait(for: [drained], timeout: 10)

        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-43"])
        let field = app.textFields["actual-km"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "9.5")
    }

    /// A typo such as "8..2" used to parse to nil, which the sheet reads as
    /// "keep the old distance", with no error shown. Now it blocks Confirm.
    func testMalformedActualKmShowsErrorAndDisablesConfirm() {
        openChecklist(row: 43)
        let field = app.textFields["actual-km"]
        replaceText(in: field, with: "8..2")
        XCTAssertTrue(app.staticTexts["actual-km-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirm-attendance"].isEnabled)

        replaceText(in: field, with: "9.5")
        XCTAssertFalse(app.staticTexts["actual-km-error"].exists)
        XCTAssertTrue(app.buttons["confirm-attendance"].isEnabled)
    }

    func testAddRunApproxKmDismissesWithDoneAndKeepsValue() {
        launch()
        tap(app.buttons["add-run"])
        let field = app.textFields["new-run-km"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: "6.5")
        tapKeyboardButton("new-run-km-keyboard-done")
        assertKeyboardDismissed()
        XCTAssertEqual(field.value as? String, "6.5")
    }
}
