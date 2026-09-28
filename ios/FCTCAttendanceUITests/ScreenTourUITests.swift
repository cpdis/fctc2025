//
//  ScreenTourUITests.swift
//  FCTCAttendanceUITests
//
//  Visits each main screen once and attaches a named screenshot. It exists for
//  visual review (before/after UI passes), not for behavior: the acceptance
//  flows live in the other suites, so the default test run skips it.
//
//  Run it with the environment variable set for the test runner:
//
//    TEST_RUNNER_FCTC_SCREEN_TOUR=1 xcodebuild test … \
//      -only-testing:FCTCAttendanceUITests/ScreenTourUITests -resultBundlePath <bundle>
//    xcrun xcresulttool export attachments --path <bundle> --output-path <dir>
//

import XCTest

@MainActor
final class ScreenTourUITests: XCTestCase {
    private var app: XCUIApplication!

    func testTourMainScreens() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FCTC_SCREEN_TOUR"] == "1",
            "Visual capture only; set TEST_RUNNER_FCTC_SCREEN_TOUR=1 to run."
        )
        continueAfterFailure = false
        app = XCUIApplication()
        // Synthetic fixture only: today's run drives the hero card, and the
        // screenshot fixture skips the Photos picker so triage can render.
        app.launchArguments = ["-ui-testing", "-ui-today-run", "-ui-screenshot-import"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
        settle()
        capture("tour-01-home")

        app.buttons["home-todays-run"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.buttons["member-Aaron"].tap()
        app.buttons["member-Dan"].tap()
        settle()
        capture("tour-02-checklist")

        app.buttons["import-poll"].tap()
        let read = app.buttons["screenshot-read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        settle()
        capture("tour-03-import")

        read.tap()
        XCTAssertTrue(app.navigationBars["Review suggestions"].waitForExistence(timeout: 5))
        settle()
        capture("tour-04-triage")
        app.buttons["triage-cancel"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))

        app.buttons["home-all-runs"].tap()
        XCTAssertTrue(app.buttons["run-row-42"].waitForExistence(timeout: 5))
        settle()
        capture("tour-05-season")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["home-unsynced"].waitForExistence(timeout: 5))
        app.buttons["home-unsynced"].tap()
        XCTAssertTrue(app.navigationBars["Outbox"].waitForExistence(timeout: 5))
        settle()
        capture("tour-06-outbox")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["home-settings"].waitForExistence(timeout: 5))
        app.buttons["home-settings"].tap()
        XCTAssertTrue(app.buttons["settings-save"].waitForExistence(timeout: 5))
        settle()
        capture("tour-07-settings")

        let version = app.staticTexts["settings-app-version"]
        for _ in 0..<6 where !(version.exists && version.isHittable) { app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 3))
        settle()
        capture("tour-08-settings-bottom")
    }

    /// Lets entrance animations finish so each shot shows the resting layout.
    /// A fixed pause is acceptable here: this test captures, it asserts nothing
    /// timing-sensitive, and XCUITest has no "animations settled" query.
    private func settle() {
        _ = app.wait(for: .runningForeground, timeout: 1)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
