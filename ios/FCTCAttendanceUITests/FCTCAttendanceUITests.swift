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

    func testTodayHeroOpensChecklist() {
        configureApp(todayHero: true)
        launch()

        let hero = app.buttons["home-todays-run"]
        XCTAssertTrue(hero.waitForExistence(timeout: 3))
        hero.tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 3))
    }

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

        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        app.buttons["home-unsynced"].tap()
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

        // Confirming a past run offers the next older unrecorded run, so dismissing
        // that prompt is what returns home. Row 43 is the older unrecorded fixture run.
        // firstMatch: alert presentation exposes each button as two identical elements.
        let done = app.buttons["catchup-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["catchup-next"].firstMatch.exists)
        done.tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
    }

    func testCatchUpPromptOpensTheOlderUnrecordedRun() {
        configureApp()
        launch()
        openRun(row: 42)

        app.buttons["member-Aaron"].tap()
        app.buttons["confirm-attendance"].tap()
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Merge —'")
        ).firstMatch.tap()

        let next = app.buttons["catchup-next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()

        // Taking the offer opens that run's checklist rather than returning home.
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["member-Aaron"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["member-Aaron"].value as? String, "Not checked")
    }

    func testOfflineQueueAppearsThenManualRetryDrainsIt() {
        configureApp(offline: true)
        launch()
        openRun(row: 43)

        app.buttons["member-Aaron"].tap()
        app.buttons["confirm-attendance"].tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))

        app.buttons["home-unsynced"].tap()
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
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
    }

    func testMilestonesSectionListsTheClosestRunners() {
        configureApp()
        launch()

        // Aaron needs 3 for 150; Col and Dan are tied needing 5 for 50.
        let aaron = app.descendants(matching: .any)["milestone-row-Aaron"]
        XCTAssertTrue(aaron.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["milestone-row-Col"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["milestone-row-Dan"].exists)
        // Dan B is 30 runs out, past the ceiling.
        XCTAssertFalse(app.descendants(matching: .any)["milestone-row-Dan B"].exists)

        XCTAssertTrue(aaron.label.contains("3 runs to 150"), aaron.label)
        // Passive: the section carries no likelihood wording from the email.
        XCTAssertFalse(app.staticTexts["Very likely"].exists)
        XCTAssertFalse(app.staticTexts["Likely"].exists)
    }

    func testMilestonesSectionShowsAVerseWhenNobodyIsClose() {
        configureApp(noMilestones: true)
        launch()

        let empty = app.descendants(matching: .any)["milestone-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["milestone-row-Aaron"].exists)
    }

    func testMilestonesPhraseIsHeldAcrossNavigation() {
        configureApp(noMilestones: true)
        launch()

        let empty = app.descendants(matching: .any)["milestone-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        let firstReading = empty.label

        // Navigate away and back. A phrase drawn in the view body would re-roll.
        app.buttons["home-all-runs"].tap()
        XCTAssertTrue(app.buttons["run-row-43"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))

        XCTAssertEqual(app.descendants(matching: .any)["milestone-empty"].label, firstReading)
    }

    private func configureApp(
        offline: Bool = false,
        screenshotFixture: ScreenshotFixture? = nil,
        resetScreenshotCoach: Bool = false,
        todayHero: Bool = false,
        noMilestones: Bool = false
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
        if todayHero { app.launchArguments.append("-ui-today-run") }
        if noMilestones { app.launchArguments.append("-ui-no-milestones") }
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
