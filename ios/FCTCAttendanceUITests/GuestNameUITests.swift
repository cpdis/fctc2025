import XCTest

@MainActor
final class GuestNameUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-shared-guests"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
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
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func openHistory() {
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-42"])
        tap(app.buttons["guest-editor"])
        tap(app.buttons["guest-history-Rene"])
        tap(app.buttons["guest-correct-name"])
    }

    func testSavedNameAppearsImmediatelyWithoutSyncingRun() {
        launch()
        openHistory()
        let field = app.textFields["guest-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Adam X")
        tap(app.buttons["guest-name-keyboard-done"])
        capture("guest-name-correction")
        tap(app.buttons["guest-name-save"])
        XCTAssertTrue(app.navigationBars["Adam X"].waitForExistence(timeout: 8))
        capture("guest-name-saved-history")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["selected-guest-Adam X"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.steppers["unnamed-guests"].value as? String, "1")
        capture("guest-name-saved-on-run")
    }

    func testStaleCorrectionCanSaveProposedName() {
        launch(["-ui-rename-conflict"])
        openHistory()
        XCTAssertTrue(app.navigationBars["Review name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["guest-name-field"].value as? String, "Adam X")
        XCTAssertTrue(app.buttons["guest-name-keep"].exists)
        capture("guest-name-conflict-review")
        tap(app.buttons["guest-name-save"])
        XCTAssertTrue(app.navigationBars["Adam X"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["guest-correct-name"].exists)
    }

    func testOutboxNameReviewCanKeepSavedName() {
        launch(["-ui-rename-conflict"])
        tap(app.buttons["home-unsynced"])
        let rename = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'outbox-rename-'")).firstMatch
        tap(rename)
        XCTAssertTrue(app.navigationBars["Review name"].waitForExistence(timeout: 5))
        capture("guest-name-outbox-review")
        tap(app.buttons["guest-name-keep"])
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "outbox-empty").firstMatch.waitForExistence(timeout: 8))
        capture("guest-name-outbox-cleared")
    }

    func testPendingNameShowsSetupReasonAfterReopening() {
        let arguments = ["-ui-rename-auth-failure", "-ui-store-name", UUID().uuidString]
        let reason = "The shared secret was rejected. Open Settings and scan a new setup code."
        launch(arguments)
        openHistory()
        let field = app.textFields["guest-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Adam X")
        tap(app.buttons["guest-name-keyboard-done"])
        tap(app.buttons["guest-name-save"])
        let pendingReason = app.staticTexts["guest-name-pending-reason"]
        XCTAssertTrue(pendingReason.waitForExistence(timeout: 8))
        XCTAssertEqual(pendingReason.label, reason)
        XCTAssertFalse(app.buttons["guest-name-save"].exists)
        XCTAssertFalse(app.buttons["guest-name-keep"].exists)
        capture("guest-name-pending-setup")

        // Reopen the persisted correction, rather than relying on local editor state.
        app.terminate()
        launch(arguments)
        tap(app.buttons["home-unsynced"])
        let savedRename = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'outbox-rename-'")).firstMatch
        XCTAssertTrue(savedRename.waitForExistence(timeout: 5))
        XCTAssertTrue(savedRename.label.contains(reason))
        capture("guest-name-outbox-setup")
        tap(savedRename)
        let savedReason = app.staticTexts["guest-name-pending-reason"]
        XCTAssertTrue(savedReason.waitForExistence(timeout: 5))
        XCTAssertEqual(savedReason.label, reason)
        tap(app.buttons["guest-name-check"])
        XCTAssertTrue(savedReason.waitForExistence(timeout: 5))
        XCTAssertEqual(savedReason.label, reason)
        XCTAssertFalse(app.buttons["guest-name-save"].exists)
        XCTAssertFalse(app.buttons["guest-name-keep"].exists)
        capture("guest-name-pending-reopened")
    }
}
