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
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))
        capture("tabs-events")

        app.tab(.dashboard).tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
        capture("tabs-dashboard")

        app.tab(.runs).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
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

    /// Each tab has its own stack: a screen pushed on Runs survives a visit to
    /// the other tabs.
    func testSwitchingTabsKeepsRunsPushedScreen() {
        launch()
        app.buttons["home-unsynced"].tap()
        XCTAssertTrue(app.navigationBars["Outbox"].waitForExistence(timeout: 5))

        app.tab(.events).tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))
        app.tab(.dashboard).tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))

        openHook("route/today-checklist")
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        settle()
        capture("route-checklist")

        // Back goes to the Runs root, not the Outbox the route replaced.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tab(.runs).isSelected)
        app.tab(.dashboard).tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
    }

    /// A route that can never resolve must not block the next one.
    func testUnresolvableRouteDoesNotBlockLaterRoutes() {
        launch(["-ui-today-run"])
        app.tab(.events).tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))

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
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))

        openHook("swap-engine")
        // The swap keeps the selected tab.
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tab(.events).isSelected)

        app.tab(.runs).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Outbox"].exists)
        app.tab(.dashboard).tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))

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
