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

    func testScreenshotTriageRequiresApplyThenReturnsToConfirm() {
        configureApp(screenshotFixture: .detail)
        launch()
        openRun(row: 43)

        var importPoll = app.buttons["import-poll"]
        XCTAssertTrue(importPoll.waitForExistence(timeout: 3))
        importPoll.tap()

        var read = app.buttons["screenshot-read"]
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        read.tap()

        XCTAssertTrue(app.navigationBars["Review suggestions"].waitForExistence(timeout: 5))
        let aaron = app.buttons["triage-auto-Aaron"]
        XCTAssertTrue(aaron.waitForExistence(timeout: 3))
        XCTAssertEqual(aaron.value as? String, "Checked")

        let danB = app.buttons["triage-choice-Dan-Dan B"]
        XCTAssertTrue(danB.waitForExistence(timeout: 3))
        danB.tap()
        XCTAssertEqual(danB.value as? String, "Selected")

        let mapPriya = app.buttons["triage-map-Priya B"]
        XCTAssertTrue(mapPriya.waitForExistence(timeout: 3))
        mapPriya.tap()
        // The bare name would also match the checklist's member row behind the
        // sheet, so menu items carry their own identifiers. firstMatch: menu
        // presentation exposes the same item as two identical Button elements.
        let colChoice = app.buttons["triage-map-pick-Col"].firstMatch
        XCTAssertTrue(colChoice.waitForExistence(timeout: 3))
        colChoice.tap()

        // Closing triage before Apply must leave the checklist unchanged.
        app.buttons["triage-cancel"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["member-Aaron"].value as? String, "Not checked")
        XCTAssertEqual(app.buttons["member-Col"].value as? String, "Not checked")
        XCTAssertEqual(app.buttons["member-Dan B"].value as? String, "Not checked")
        XCTAssertFalse(app.buttons["member-Priya B"].exists)

        importPoll = app.buttons["import-poll"]
        importPoll.tap()
        read = app.buttons["screenshot-read"]
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        read.tap()
        XCTAssertTrue(app.navigationBars["Review suggestions"].waitForExistence(timeout: 5))
        app.buttons["triage-choice-Dan-Dan B"].tap()
        app.buttons["triage-add-Priya B"].tap()
        app.buttons["triage-apply"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["member-Aaron"].value as? String, "Checked")
        XCTAssertEqual(app.buttons["member-Dan B"].value as? String, "Checked")
        XCTAssertEqual(app.buttons["member-Priya B"].value as? String, "Checked")
        // Applying proposals only changes the draft. The sheet write still needs the
        // existing explicit Confirm action.
        XCTAssertTrue(app.buttons["confirm-attendance"].exists)
    }

    func testScreenshotNamelessCardShowsRecoveryCoach() {
        configureApp(screenshotFixture: .nameless)
        launch()
        openRun(row: 43)

        app.buttons["import-poll"].tap()
        let read = app.buttons["screenshot-read"]
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        read.tap()

        let hint = app.descendants(matching: .any)["screenshot-nameless-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        app.buttons["Show instructions"].tap()
        XCTAssertTrue(app.buttons["screenshot-coach-continue"].waitForExistence(timeout: 3))
    }

    func testScreenshotCoachCanBeHiddenForLaterImports() {
        configureApp(screenshotFixture: .coach, resetScreenshotCoach: true)
        launch()
        openRun(row: 43)

        app.buttons["import-poll"].tap()
        let continueButton = app.buttons["screenshot-coach-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        continueButton.tap()
        XCTAssertTrue(app.buttons["screenshot-read"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()

        // Start a fresh process without the reset argument. This proves the
        // preference is persisted, rather than only held in the sheet's state.
        app.terminate()
        configureApp(screenshotFixture: .coach)
        launch()
        openRun(row: 43)
        app.buttons["import-poll"].tap()
        XCTAssertTrue(app.buttons["screenshot-read"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["screenshot-coach-continue"].exists)
    }

    private func launch() {
        app.launch()
        XCTAssertTrue(app.navigationBars["FCTC"].waitForExistence(timeout: 5))
    }

    private func configureApp(
        offline: Bool = false,
        screenshotFixture: ScreenshotFixture? = nil,
        resetScreenshotCoach: Bool = false
    ) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryXL",
        ]
        if offline { app.launchArguments.append("-ui-offline") }
        if let screenshotFixture {
            app.launchArguments.append(screenshotFixture.launchArgument)
        }
        if resetScreenshotCoach {
            app.launchArguments.append("-ui-reset-screenshot-coach")
        }
    }

    private func openRun(row: Int) {
        app.buttons["home-all-runs"].tap()
        let run = app.buttons["run-row-\(row)"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 3))
    }

}

private enum ScreenshotFixture {
    case detail
    case nameless
    case coach

    var launchArgument: String {
        switch self {
        case .detail: "-ui-screenshot-import"
        case .nameless: "-ui-screenshot-nameless"
        case .coach: "-ui-screenshot-coach"
        }
    }
}
