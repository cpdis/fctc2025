import XCTest

/// Run cancelled (docs/plans/2026-11-23-1050-feat-run-cancelled-plan.md, U4).
/// The blank row-43 run is cancelled from the footer row, shows its cancelled
/// state and the run list's badge, then is restored.
@MainActor
final class RunCancellationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// AE2's happy path, R3, R6, R9.
    func testCancelAndRestore() {
        launch()
        openRun(43)
        tap(app.buttons["cancel-run"])
        let confirm = app.buttons["confirm-cancel-run"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture("2-confirm")
        confirm.tap()

        XCTAssertTrue(app.descendants(matching: .any)["cancelled-run-status"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["confirm-attendance"].exists, "A cancelled run has no Confirm")
        capture("3-cancelled")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.buttons["run-row-43"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.hasSuffix("Cancelled"), row.label)
        capture("4-run-list")

        row.tap()
        tap(app.buttons["restore-run"])
        XCTAssertTrue(app.buttons["guest-editor"].waitForExistence(timeout: 8), "Restore returns the ordinary checklist")
    }

    /// R3: a run with attendance offers no cancel.
    func testRecordedRunOffersNoCancel() {
        launch()
        openRun(42)
        app.swipeUp(); app.swipeUp()
        XCTAssertFalse(app.buttons["cancel-run"].exists)
    }

    /// R8: today's cancelled run reads Cancelled on Home and opens its cancelled state.
    func testHomeShowsTodayCancelled() {
        launch(extra: ["-ui-today-cancelled"])
        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Cancelled'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        capture("home-today-cancelled")
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cancelled-run-status"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirm-attendance"].exists, "A cancelled run has no Confirm")
    }

    private func launch(extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-shared-guests"] + extra
        if ProcessInfo.processInfo.environment["FCTC_UI_LARGE_TEXT"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
    }

    private func openRun(_ row: Int) {
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-\(row)"])
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
    }

    private func tap(_ element: XCUIElement) {
        for _ in 0..<7 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "run-cancelled-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
