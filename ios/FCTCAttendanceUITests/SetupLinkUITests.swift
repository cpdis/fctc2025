//
//  SetupLinkUITests.swift
//  FCTCAttendanceUITests
//
//  Any web page or chat message can open `fctc-attendance://setup?…`. These pin
//  the confirmation a foreign link gets, and prove Cancel leaves the fixture
//  connection (https://ui-test.invalid/exec, "UI Test iPhone") alone.
//

import XCTest

@MainActor
final class SetupLinkUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Shaped like a real deployment: shared `AKfycb` prefix, unique tail.
    private let foreignLink = "fctc-attendance://setup"
        + "?endpoint=https%3A%2F%2Fscript.google.com%2Fmacros%2Fs%2FAKfycbzForeignDeployment0000000000000000x9Qc%2Fexec"
        + "&secret=not-the-club-secret&device=Run%20phone"

    override func setUp() {
        continueAfterFailure = false
    }

    func testForeignLinkNamesDeploymentAndWarnsBeforeReplacing() {
        // The promoted-conflict seed leaves one outstanding row for the fixture endpoint.
        launch(["-ui-shared-guests", "-ui-promoted-conflict"])
        app.open(URL(string: foreignLink)!)

        let alert = app.alerts["Replace the sheet connection?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        assert(alert, shows: "Sheet: AKfy…x9Qc")
        assert(alert, shows: "Device: Run phone")
        assert(alert, shows: "This replaces the current sheet, ui-test.invalid/exec.")
        assert(alert, shows: "The app will not send 1 submission that is waiting to sync.")
        XCTAssertTrue(alert.buttons["Replace"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "setup-link-replace-alert"
        shot.lifetime = .keepAlways
        add(shot)

        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
        assertFixtureConnectionUnchanged()
    }

    func testSameDeploymentLinkSaysItOnlyUpdatesTheConnection() {
        launch()
        app.open(URL(string: "fctc-attendance://setup?endpoint=https%3A%2F%2Fui-test.invalid%2Fexec&secret=rotated&device=Run%20phone")!)

        let alert = app.alerts["Update this connection?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        assert(alert, shows: "Sheet: ui-test.invalid/exec")
        assert(alert, shows: "This phone already uses this sheet.")

        alert.buttons["Cancel"].tap()
        assertFixtureConnectionUnchanged()
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
    }

    /// The alert message is one static text, so match a fragment of it.
    private func assert(_ alert: XCUIElement, shows fragment: String, line: UInt = #line) {
        let text = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
        XCTAssertTrue(text.exists, "Alert is missing “\(fragment)”", line: line)
    }

    /// Settings loads from the saved configuration, so its fields prove nothing moved.
    private func assertFixtureConnectionUnchanged() {
        app.buttons["home-settings"].tap()
        let endpoint = app.textFields["settings-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
        XCTAssertEqual(endpoint.value as? String, "https://ui-test.invalid/exec")
        XCTAssertEqual(app.textFields["settings-device-name"].value as? String, "UI Test iPhone")
    }
}
