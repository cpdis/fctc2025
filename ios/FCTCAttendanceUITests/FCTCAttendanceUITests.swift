//
//  FCTCAttendanceUITests.swift
//  FCTCAttendanceUITests
//
//  U4 acceptance flows. The app's `-ui-testing` mode uses an in-memory cache and a
//  deterministic SheetAPIClient, so these tests never need credentials or a network.
//

import XCTest

@MainActor
final class FCTCAttendanceUITests: XCTestCase {
    private var app: XCUIApplication!

    func testRecordConfirmAndDrainLeavesClearOutbox() {
        configureApp()
        launch()
        openRun(row: 43)

        let aaron = app.buttons["member-Aaron"]
        XCTAssertTrue(aaron.waitForExistence(timeout: 3))
        XCTAssertEqual(aaron.value as? String, "Not checked")
        aaron.tap()
        XCTAssertEqual(aaron.value as? String, "Checked")
        app.buttons["confirm-attendance"].tap()

        XCTAssertTrue(app.navigationBars["FCTC"].waitForExistence(timeout: 5))
        app.buttons["home-outbox"].tap()
        XCTAssertTrue(outboxEmpty.waitForExistence(timeout: 5))
    }

    func testRecordedRunShowsMergeAndOverwriteWarning() {
        configureApp()
        launch()
        openRun(row: 42)

        app.buttons["member-Aaron"].tap()
        app.buttons["confirm-attendance"].tap()

        let merge = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Merge —'")
        ).firstMatch
        let overwrite = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Overwrite —'")
        ).firstMatch
        XCTAssertTrue(merge.waitForExistence(timeout: 3))
        XCTAssertTrue(overwrite.exists)
        merge.tap()
        XCTAssertTrue(app.navigationBars["FCTC"].waitForExistence(timeout: 5))
    }

    func testOfflineQueueAppearsThenManualRetryDrainsIt() {
        configureApp(offline: true)
        launch()
        openRun(row: 43)

        app.buttons["member-Aaron"].tap()
        app.buttons["confirm-attendance"].tap()
        XCTAssertTrue(app.navigationBars["FCTC"].waitForExistence(timeout: 5))

        app.buttons["home-outbox"].tap()
        let queued = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'outbox-row-'")
        ).firstMatch
        XCTAssertTrue(queued.waitForExistence(timeout: 5))

        app.buttons["outbox-retry"].tap()
        XCTAssertTrue(outboxEmpty.waitForExistence(timeout: 5))
    }

    /// SwiftUI attaches ContentUnavailableView's identifier to its text and image
    /// children rather than to an `.other` container, so match on any element type.
    private var outboxEmpty: XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'outbox-empty'")
        ).firstMatch
    }

    func testAddPersonAppearsAlphabeticallyWithoutRefresh() {
        configureApp()
        launch()
        openRun(row: 43)

        let addPerson = app.textFields["add-person-field"]
        XCTAssertTrue(addPerson.waitForExistence(timeout: 3))
        addPerson.tap()
        addPerson.typeText("Bilbo\n")

        let aaron = app.buttons["member-Aaron"]
        let bilbo = app.buttons["member-Bilbo"]
        let col = app.buttons["member-Col"]
        XCTAssertTrue(bilbo.waitForExistence(timeout: 5))
        XCTAssertLessThan(aaron.frame.minY, bilbo.frame.minY)
        XCTAssertLessThan(bilbo.frame.minY, col.frame.minY)
    }

    private func launch() {
        app.launch()
        XCTAssertTrue(app.navigationBars["FCTC"].waitForExistence(timeout: 5))
    }

    private func configureApp(offline: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryXL",
        ]
        if offline { app.launchArguments.append("-ui-offline") }
    }

    private func openRun(row: Int) {
        app.buttons["home-all-runs"].tap()
        let run = app.buttons["run-row-\(row)"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 3))
    }

}
