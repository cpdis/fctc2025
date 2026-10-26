//
//  TabNavigationUITests.swift
//  FCTCAttendanceUITests
//
//  The Runs · Events · Dashboard tab shell (R19) and how pushed screens share
//  the bottom edge with the tab bar (U11): the run picker and the checklist hide
//  the tab bar so their bottom search field (and the picker's Review button)
//  own that edge, and the tab bar returns when they pop. Also the root-owned
//  routing (KTD14): per-tab stacks, routes landing on Runs, and engine swaps.
//

import XCTest

@MainActor
final class TabNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    func testTabsShowTheirRootScreens() {
        launch()
        capture("tabs-runs")

        app.tab(.events).tap()
        XCTAssertTrue(app.staticTexts["events-title"].waitForExistence(timeout: 5))
        capture("tabs-events")

        app.tab(.dashboard).tap()
        XCTAssertTrue(app.staticTexts["dashboard-title"].waitForExistence(timeout: 5))
        capture("tabs-dashboard")

        app.tab(.runs).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
    }

    /// The three tab titles sit at one height (Colin's review): each root draws
    /// the same TabHeader row instead of the system large title.
    func testTabTitlesShareOneHeight() {
        launch(["-ui-shared-guests", "-ui-dashboard"])
        let runs = app.staticTexts["home-title"]
        XCTAssertTrue(runs.waitForExistence(timeout: 5))
        settle()
        // Centres, not tops: in a List row holding only the title, the row takes
        // the title's identifier, so Events reports the 52 pt row, not the text.
        let middle = runs.frame.midY
        let left = runs.frame.minX

        app.tab(.events).tap()
        let events = app.staticTexts["events-title"]
        XCTAssertTrue(events.waitForExistence(timeout: 5))
        settle()
        XCTAssertEqual(events.frame.midY, middle, accuracy: 0.5, "Events title is not level with FCTC")

        app.tab(.dashboard).tap()
        let dashboard = app.staticTexts["dashboard-title"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        settle()
        XCTAssertEqual(dashboard.frame.midY, middle, accuracy: 0.5, "Dashboard title is not level with FCTC")
        XCTAssertEqual(dashboard.frame.minX, left, accuracy: 0.5, "Dashboard title is not flush with FCTC")
    }

    /// Runs keeps today's run and the tiles (R20); Milestones and Birthdays
    /// moved to Events (R22).
    func testLaunchShowsRunsWithTodaysRunAndTiles() {
        launch(["-ui-today-run"])
        XCTAssertTrue(app.tab(.runs).isSelected)
        XCTAssertTrue(app.buttons["home-todays-run"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-this-week"].exists)
        XCTAssertTrue(app.buttons["home-unsynced"].exists)
        XCTAssertTrue(app.buttons["home-all-runs"].exists)
        XCTAssertTrue(app.buttons["home-past-runs"].exists)
        XCTAssertTrue(app.buttons["home-settings"].exists)
        let milestone = app.descendants(matching: .any)["milestone-row-Aaron"]
        let birthdays = app.descendants(matching: .any)["birthday-empty"]
        XCTAssertFalse(milestone.exists, "Milestones still on Runs")
        XCTAssertFalse(birthdays.exists, "Birthdays still on Runs")

        app.tab(.events).tap()
        XCTAssertTrue(milestone.waitForExistence(timeout: 5))
        XCTAssertTrue(birthdays.exists)
    }

    /// Sync sits next to the gear and reads the sheet again. A pill above the
    /// tab bar follows the read: checking, then the time it landed, then it
    /// hides. `-ui-slow-sheet` holds each read for 3 s.
    func testSyncButtonShowsProgressThenTheUpdateTime() {
        launch(["-ui-today-run", "-ui-slow-sheet"])
        let sync = app.buttons["home-sync"]
        let pill = app.descendants(matching: .any)["home-sync-status"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-settings"].exists)
        // The launch read shows the pill too. Start from a clean screen.
        XCTAssertTrue(pill.waitForNonExistence(timeout: 10), "The launch pill never hid")

        sync.tap()
        XCTAssertTrue(waitFor("home-sync-status", labelContaining: "Checking the sheet", timeout: 2), "Sync shows no progress")
        XCTAssertEqual(sync.value as? String, "Checking the sheet…")
        XCTAssertTrue(waitFor("home-sync-status", labelContaining: "Updated", timeout: 5), "Sync never finished")
        XCTAssertEqual(sync.value as? String ?? "", "", "The Sync button still reports work")
        capture("runs-sync-updated")
        assertTickHolds()
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5), "The pill never hid")
    }

    /// A confirmed check-in sends from Runs: the pill reads "Sending 1 change…"
    /// and the Unsynced tile reports syncing, then both stop when the write
    /// lands. `-ui-slow-sheet` holds the write for 3 s.
    func testSendShowsProgressThenStops() {
        launch(["-ui-slow-sheet"])
        let pill = app.descendants(matching: .any)["home-sync-status"]
        let tile = app.buttons["home-unsynced"]
        XCTAssertTrue(pill.waitForNonExistence(timeout: 10), "The launch pill never hid")

        app.buttons["home-all-runs"].tap()
        let run = app.buttons["run-row-43"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        let aaron = app.buttons["member-Aaron"]
        XCTAssertTrue(aaron.waitForExistence(timeout: 5))
        aaron.tap()
        app.buttons["confirm-attendance"].tap()

        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor("home-sync-status", labelContaining: "Sending 1 change", timeout: 3), "The send shows no progress")
        XCTAssertTrue(tile.label.contains("syncing"), tile.label)
        capture("runs-sending")
        XCTAssertTrue(waitFor("home-sync-status", labelContaining: "Updated", timeout: 6), "The send never finished")
        XCTAssertFalse(tile.label.contains("syncing"), "The tile still reports a send")
        assertTickHolds()
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5), "The pill never hid")
    }

    /// A return to Runs within 5 minutes of a good sync does not read the
    /// sheet again (Colin's review of build 12: it read 5 s after a read).
    /// Sync still reads at once.
    func testReturningToRunsSoonAfterASyncDoesNotReadAgain() {
        launch(["-ui-slow-sheet"])
        let pill = app.descendants(matching: .any)["home-sync-status"]
        XCTAssertTrue(pill.waitForNonExistence(timeout: 10), "The launch pill never hid")

        app.buttons["home-all-runs"].tap()
        XCTAssertTrue(app.buttons["run-row-43"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            waitFor("home-sync-status", labelContaining: "Checking the sheet", timeout: 2),
            "Runs read the sheet again on return"
        )

        app.buttons["home-sync"].tap()
        XCTAssertTrue(waitFor("home-sync-status", labelContaining: "Checking the sheet", timeout: 2), "Sync did not read")
    }

    /// The "Updated" tick holds 2 s. A cancelled hide timer once cut it to
    /// 0.2 s, because one sync moves the sync time twice. One `exists` read
    /// 0.5 s on: a short `waitForExistence` can give up before its snapshot.
    private func assertTickHolds() {
        Thread.sleep(forTimeInterval: 0.5)
        let tick = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'home-sync-status' AND label CONTAINS 'Updated'"))
            .firstMatch
        XCTAssertTrue(tick.exists, "The tick did not hold")
    }

    /// Each tab has its own stack: a screen pushed on Runs survives a visit to
    /// the other tabs.
    func testSwitchingTabsKeepsRunsPushedScreen() {
        launch()
        app.buttons["home-unsynced"].tap()
        XCTAssertTrue(app.navigationBars["Outbox"].waitForExistence(timeout: 5))

        app.tab(.events).tap()
        XCTAssertTrue(app.staticTexts["events-title"].waitForExistence(timeout: 5))
        app.tab(.dashboard).tap()
        XCTAssertTrue(app.staticTexts["dashboard-title"].waitForExistence(timeout: 5))
        app.tab(.runs).tap()
        XCTAssertTrue(app.navigationBars["Outbox"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
    }

    /// A "today's checklist" route (App Intent) from Dashboard selects Runs,
    /// pops its pushed Outbox and opens the checklist (R21, KTD14).
    func testTodayRouteFromDashboardOpensChecklistOnRuns() {
        launch(["-ui-today-run"])
        app.buttons["home-unsynced"].tap()
        XCTAssertTrue(app.navigationBars["Outbox"].waitForExistence(timeout: 5))
        app.tab(.dashboard).tap()
        XCTAssertTrue(app.staticTexts["dashboard-title"].waitForExistence(timeout: 5))

        openHook("route/today-checklist")
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        settle()
        capture("route-checklist")

        // Back goes to the Runs root, not the Outbox the route replaced.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tab(.runs).isSelected)
        app.tab(.dashboard).tap()
        XCTAssertTrue(app.staticTexts["dashboard-title"].waitForExistence(timeout: 5))
    }

    /// UI-NEW-1: the dictation route opens the voice sheet once. Popping back
    /// from Guests re-runs the checklist's `.task`, which reopened it.
    func testDictationRouteOpensVoiceSheetOnlyOnce() {
        launch(["-ui-today-run"])
        openHook("route/today-dictation")
        let voiceSheet = app.navigationBars["Dictate Attendance"]
        XCTAssertTrue(voiceSheet.waitForExistence(timeout: 8))
        answerSpeechPrompt()
        voiceSheet.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))

        app.buttons["guest-editor"].tap()
        XCTAssertTrue(app.navigationBars["Guests"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        settle()
        XCTAssertFalse(voiceSheet.exists)
        capture("dictation-route-after-pop")
    }

    /// The first dictation on a fresh simulator asks for speech access. Either
    /// answer leaves the sheet's Cancel button in place.
    private func answerSpeechPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don'")).firstMatch
        // Speech and the microphone may each ask once.
        for _ in 0..<2 where deny.waitForExistence(timeout: 3) { deny.tap() }
    }

    /// A route that can never resolve must not block the next one.
    func testUnresolvableRouteDoesNotBlockLaterRoutes() {
        launch(["-ui-today-run"])
        app.tab(.events).tap()
        XCTAssertTrue(app.staticTexts["events-title"].waitForExistence(timeout: 5))

        openHook("route/missing-run")
        // It lands on Runs and waits there for a run that never arrives.
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review & Confirm"].exists)

        openHook("route/today-checklist")
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
    }

    /// A connection change swaps the engine, and no tab may keep a screen
    /// pushed for the old connection: the Outbox on Runs and the Run log on
    /// Dashboard both pop. Events pushes nothing.
    func testEngineSwapReturnsEveryTabToItsRoot() {
        launch()
        app.buttons["home-unsynced"].tap()
        XCTAssertTrue(app.navigationBars["Outbox"].waitForExistence(timeout: 5))
        app.tab(.dashboard).tap()
        let runLog = app.descendants(matching: .any)["dashboard-run-log"].firstMatch
        for _ in 0..<8 where !(runLog.exists && runLog.isHittable) { app.swipeUp() }
        runLog.tap()
        XCTAssertTrue(app.navigationBars["Run log"].waitForExistence(timeout: 5))
        app.tab(.events).tap()
        XCTAssertTrue(app.staticTexts["events-title"].waitForExistence(timeout: 5))

        openHook("swap-engine")
        // The swap keeps the selected tab.
        XCTAssertTrue(app.staticTexts["events-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tab(.events).isSelected)

        app.tab(.runs).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Outbox"].exists)
        app.tab(.dashboard).tap()
        XCTAssertTrue(app.staticTexts["dashboard-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Run log"].exists)
    }

    /// A route still waiting when the connection changes named a run in the
    /// old connection's sheet, so the swap drops it: it must not land on the
    /// new sheet's run. The old sheet has no run today, so a today route waits;
    /// the new sheet has one.
    func testEngineSwapDropsAWaitingRoute() {
        launch()
        XCTAssertTrue(app.buttons["home-no-run-today"].waitForExistence(timeout: 5))
        app.tab(.events).tap()
        XCTAssertTrue(app.staticTexts["events-title"].waitForExistence(timeout: 5))

        openHook("route/today-checklist")
        // It lands on Runs and waits there for a run today.
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tab(.runs).isSelected)
        XCTAssertFalse(app.navigationBars["Review & Confirm"].exists)

        openHook("swap-engine/today-run")
        // Give the new sheet time to load, then check nothing opened on it.
        XCTAssertFalse(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 4),
                       "The old connection's route opened the new sheet's run")
        XCTAssertTrue(app.buttons["home-todays-run"].waitForExistence(timeout: 5))

        // A new route still lands on the new connection's run.
        openHook("route/today-checklist")
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
    }

    /// Push, pop (Back button), re-push, pop (edge swipe): the tab bar hides on
    /// every push and returns on every pop, whichever way the pop happens.
    func testRunPickerHidesTabBarOnEveryPushAndRestoresItOnPop() {
        launch()
        XCTAssertTrue(tabBarIsVisible)

        for pass in 1...2 {
            app.buttons["home-all-runs"].tap()
            XCTAssertTrue(app.buttons["run-row-43"].waitForExistence(timeout: 5))
            settle()
            capture("season-push-\(pass)")
            XCTAssertFalse(tabBarIsVisible, "Tab bar still visible on push \(pass)")
            XCTAssertTrue(app.buttons["review-default-run"].isHittable)
            XCTAssertTrue(app.searchFields.firstMatch.isHittable)

            if pass == 1 {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                swipeBack()
            }
            XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
            settle()
            XCTAssertTrue(tabBarIsVisible, "Tab bar missing after pop \(pass)")
        }
        capture("runs-after-pops")
    }

    /// The bottom-bar search still filters and Review still opens the default run.
    func testRunPickerBottomSearchAndReviewStillWork() {
        launch()
        app.buttons["home-all-runs"].tap()
        let review = app.buttons["review-default-run"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))

        // Review opens the default (unrecorded) run's checklist.
        review.tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        settle()
        capture("checklist-from-review")
        XCTAssertFalse(tabBarIsVisible, "Tab bar showed on the checklist")
        XCTAssertTrue(app.searchFields.firstMatch.isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["run-row-43"].waitForExistence(timeout: 5))
        settle()
        XCTAssertFalse(tabBarIsVisible, "Tab bar came back after popping to the picker")

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("River")
        XCTAssertTrue(app.buttons["run-row-43"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["run-row-42"].exists)
        settle()
        capture("season-search")
    }

    /// This Week pushes the same picker, so it hides the tab bar the same way.
    func testThisWeekPickerHidesTabBar() {
        launch(["-ui-today-run"])
        app.buttons["home-this-week"].tap()
        XCTAssertTrue(app.buttons["run-row-42"].waitForExistence(timeout: 5))
        settle()
        capture("this-week")
        XCTAssertFalse(tabBarIsVisible)
        XCTAssertTrue(app.searchFields.firstMatch.isHittable)
    }

    /// The checklist also hides the tab bar and keeps its search at the bottom,
    /// whether it opens from the hero (tab bar showing) or from the picker.
    func testChecklistHidesTabBarAndKeepsBottomSearch() {
        launch(["-ui-today-run"])
        app.buttons["home-todays-run"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        settle()
        capture("checklist-from-home")
        XCTAssertFalse(tabBarIsVisible)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(search.frame.minY, app.frame.midY, "Search left the bottom bar")
        search.tap()
        search.typeText("Aa")
        XCTAssertTrue(app.buttons["member-Aaron"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["member-Col"].exists)
        settle()
        capture("checklist-search")
    }

    // MARK: - Helpers

    private func launch(_ extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
    }

    /// Fires a UI-test hook (`UITestSupport.handleHook`) in the running app.
    /// Through the system, not `app.open`, which relaunches the app and would
    /// wipe the very tab and stack state these tests check.
    private func openHook(_ hook: String) {
        XCUIDevice.shared.system.open(URL(string: "fctc-attendance://ui-test/\(hook)")!)
    }

    /// A hidden tab bar can stay in the accessibility tree off screen, so
    /// "visible" means present and hittable.
    private var tabBarIsVisible: Bool {
        let bar = app.tabBars.firstMatch
        return bar.exists && bar.isHittable
    }

    /// The interactive pop: drag from the leading edge to mid-screen.
    private func swipeBack() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Lets push and pop transitions finish before a visibility check or capture.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Waits until an element with `identifier` has a label containing `text`.
    /// It matches afresh on every check: the sync pill changes element type
    /// (an activity indicator while it spins, then a tick), and an element
    /// resolved once kept looking for the old type.
    private func waitFor(_ identifier: String, labelContaining text: String, timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", identifier, text))
            .firstMatch
            .waitForExistence(timeout: timeout)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The tab bar's buttons, in tab-bar order.
enum AppTabButton: Int {
    case runs, events, dashboard

    var identifier: String { "tab-\(self)" }
}

extension XCUIApplication {
    /// A tab bar button. iPhone tab buttons can drop a SwiftUI `Tab`'s
    /// accessibility identifier on iOS 26, so fall back to its position.
    func tab(_ tab: AppTabButton) -> XCUIElement {
        let byIdentifier = tabBars.buttons[tab.identifier]
        return byIdentifier.exists ? byIdentifier : tabBars.buttons.element(boundBy: tab.rawValue)
    }
}
