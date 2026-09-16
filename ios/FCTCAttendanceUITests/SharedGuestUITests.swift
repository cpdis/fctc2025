import XCTest

@MainActor
final class SharedGuestUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-shared-guests"] + extra
        if ProcessInfo.processInfo.environment["FCTC_UI_LARGE_TEXT"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
    }
    private func openRun(_ row: Int) {
        app.buttons["home-all-runs"].tap()
        let button = app.buttons["run-row-\(row)"]
        if !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
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
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSharedGuestSelectionAndSavedNames() {
        launch()
        openRun(42)
        capture("shared-guests-member-checklist")
        app.buttons["guest-editor"].tap()
        XCTAssertTrue(app.staticTexts["selected-guest-Rene"].waitForExistence(timeout: 5))
        capture("shared-guests-saved-selection")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.buttons["run-row-43"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        app.buttons["guest-editor"].tap()
        XCTAssertTrue(app.buttons["select-guest-Rene"].waitForExistence(timeout: 5))
        capture("shared-guests-returning-list")
        app.buttons["select-guest-Rene"].tap()
        XCTAssertTrue(app.staticTexts["selected-guest-Rene"].waitForExistence(timeout: 5))
    }

    func testGuestHistoryAndPromotionPreview() {
        launch()
        openRun(43)
        app.buttons["guest-editor"].tap()
        app.buttons["guest-history-Rene"].tap()
        XCTAssertTrue(app.navigationBars["Rene"].waitForExistence(timeout: 5))
        capture("shared-guests-history")
        app.buttons["guest-promote"].tap()
        app.buttons["promotion-preview"].tap()
        let save = app.buttons["Save run and review promotion"].firstMatch
        if save.waitForExistence(timeout: 2) { save.tap() }
        XCTAssertTrue(app.staticTexts["promotion-confirmed-count"].waitForExistence(timeout: 8))
        capture("shared-guests-promotion-preview")
        tap(app.buttons["promotion-confirm"])
        XCTAssertTrue(app.staticTexts["Added as a member with 11 recorded runs."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["promotion-confirm"].exists)
        capture("shared-guests-promotion-completed")
    }
    func testRecoveryReminderCanBeDismissedAndReopenedAfterRelaunch() {
        let store = UUID().uuidString
        launch(["-ui-recovery", "-ui-store-name", store])
        app.buttons["home-settings"].tap()
        let recovery = app.buttons["settings-recover-guests"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 5)); recovery.tap()
        let candidate = app.buttons["recovery-candidate-Rene-pending"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        capture("shared-guests-recovery-list")
        candidate.tap()
        capture("shared-guests-recovery-review")
        let dismiss = app.buttons["recovery-dismiss"]
        if !dismiss.isHittable { app.swipeUp() }
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5)); dismiss.tap()
        app.terminate()
        launch(["-ui-store-name", store])
        app.buttons["home-settings"].tap()
        app.buttons["settings-recover-guests"].tap()
        let dismissed = app.buttons["recovery-candidate-Rene-dismissed"]
        XCTAssertTrue(dismissed.waitForExistence(timeout: 5))
        dismissed.tap()
        let reopen = app.buttons["recovery-dismiss"]
        if !reopen.isHittable { app.swipeUp() }
        XCTAssertEqual(reopen.label, "Reopen for review")
    }

    func testPendingPromotionSurvivesRelaunchAndDoesNotOfferAnotherPromotion() {
        let store = UUID().uuidString
        launch(["-ui-pending-promotion", "-ui-store-name", store])
        app.terminate()
        launch(["-ui-store-name", store])
        openRun(43)
        app.buttons["guest-editor"].tap()
        app.buttons["guest-history-Rene"].tap()
        XCTAssertTrue(app.buttons["guest-pending-promotion"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["guest-promote"].exists)
        app.buttons["guest-pending-promotion"].tap()
        capture("shared-guests-pending-promotion")
        XCTAssertTrue(app.buttons["Check receipt"].waitForExistence(timeout: 5))
    }

    func testSavedRunRemainsSavedWhenPromotionPreviewFails() {
        launch(["-ui-promotion-fails"])
        openRun(43)
        app.buttons["guest-editor"].tap()
        app.buttons["select-guest-Toby"].tap()
        app.buttons["guest-history-Toby"].tap()
        app.buttons["guest-promote"].tap()
        app.buttons["promotion-preview"].tap()
        app.buttons["Save run and review promotion"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Run saved."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Promotion has not completed. The run is saved."].exists)
        capture("shared-guests-saved-run-promotion-failed")
    }

    func testRecoveryImportsOnlyAfterExplicitReviewAndRemembersReceipt() {
        let store = UUID().uuidString
        launch(["-ui-recovery", "-ui-store-name", store])
        app.buttons["home-settings"].tap()
        app.buttons["settings-recover-guests"].tap()
        app.buttons["recovery-candidate-Rene-pending"].tap()
        tap(app.buttons["recovery-person"])
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rene ·'")).firstMatch.tap()
        tap(app.buttons["recovery-season"])
        app.buttons[String(Calendar.current.component(.year, from: Date()))].firstMatch.tap()
        tap(app.buttons["recovery-run"])
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Soft Sand' AND label CONTAINS 'unnamed'")).firstMatch.tap()
        let toggle = app.switches["recovery-verified"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if !toggle.isHittable { app.swipeUp() }
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        tap(app.buttons["recovery-preview"])
        app.swipeUp()
        XCTAssertTrue(app.buttons["recovery-confirm-import"].waitForExistence(timeout: 8))
        capture("shared-guests-recovery-import-preview")
        tap(app.buttons["recovery-confirm-import"])
        XCTAssertTrue(app.staticTexts["Imported and confirmed"].waitForExistence(timeout: 8))
        app.terminate()
        launch(["-ui-store-name", store])
        app.buttons["home-settings"].tap()
        app.buttons["settings-recover-guests"].tap()
        XCTAssertTrue(app.buttons["recovery-candidate-Rene-imported"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recovery-candidate-Rene-pending"].exists)
    }

    func testLargeTextReturningGuestList() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-43"])
        tap(app.buttons["guest-editor"])
        capture("shared-guests-large-text-top")
        tap(app.buttons["select-guest-Rene"])
        capture("shared-guests-large-text-selection")
    }

    func testNamingSavedUnnamedGuestRequiresReviewedOverwrite() {
        launch()
        openRun(42)
        app.buttons["guest-editor"].tap()
        app.buttons["name-unnamed-guest"].tap()
        tap(app.buttons["select-guest-Toby"])
        XCTAssertTrue(app.staticTexts["selected-guest-Toby"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["confirm-attendance"].tap()
        XCTAssertTrue(app.buttons["confirm-overwrite"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirm-merge"].exists)
        capture("shared-guests-unnamed-assignment-review")
        app.buttons["confirm-overwrite"].firstMatch.tap()
        if app.buttons["catchup-done"].firstMatch.waitForExistence(timeout: 3) { app.buttons["catchup-done"].firstMatch.tap() }
        if app.buttons["home-all-runs"].waitForExistence(timeout: 3) { app.buttons["home-all-runs"].tap() }
        let row = app.buttons["run-row-42"]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        app.buttons["guest-editor"].tap()
        XCTAssertTrue(app.staticTexts["selected-guest-Rene"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["selected-guest-Toby"].exists)
        XCTAssertEqual(app.steppers["unnamed-guests"].value as? String, "0")
        capture("shared-guests-unnamed-assignment-saved")
    }

    func testPromotedMergeReviewKeepsConcurrentAttendance() {
        openPromotedConflict(overwrite: false)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Members, Col, Dan, Rene'")).count, 2)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Named guests, Toby'")).count, 2)
        XCTAssertTrue(app.staticTexts["Distance, 8.1 km"].exists)
        XCTAssertFalse(app.staticTexts["Removals in this overwrite"].exists)
        capture("shared-guests-promoted-merge-review")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Distance, 7.1 km"].exists)
        capture("shared-guests-promoted-merge-after")
    }

    func testPromotedOverwriteReviewShowsCurrentRemovals() {
        openPromotedConflict(overwrite: true)
        XCTAssertTrue(app.staticTexts["Members, Col, Rene"].exists)
        XCTAssertTrue(app.staticTexts["Members, Dan"].exists)
        XCTAssertTrue(app.staticTexts["Named guests, Toby"].exists)
        tap(app.buttons["save-promoted-conversion"])
        XCTAssertTrue(app.staticTexts["Outbox Clear"].waitForExistence(timeout: 8))
    }

    private func openPromotedConflict(overwrite: Bool) {
        launch(["-ui-promoted-conflict"] + (overwrite ? ["-ui-promoted-overwrite"] : []))
        app.buttons["home-unsynced"].tap()
        let conflict = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'outbox-conflict-' ")).firstMatch
        XCTAssertTrue(conflict.waitForExistence(timeout: 5)); conflict.tap()
        XCTAssertTrue(app.staticTexts["Members, Col, Dan, Rene"].firstMatch.waitForExistence(timeout: 8))
        if overwrite {
            app.swipeUp()
            XCTAssertTrue(app.staticTexts["Removals in this overwrite"].waitForExistence(timeout: 5))
            capture("shared-guests-promoted-overwrite-removals")
        }
    }

}
