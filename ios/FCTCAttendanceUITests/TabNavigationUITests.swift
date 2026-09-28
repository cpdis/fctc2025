//
//  TabNavigationUITests.swift
//  FCTCAttendanceUITests
//
//  The Runs · Events · Dashboard tab shell (R19) and how pushed screens share
//  the bottom edge with the tab bar (U11): the run picker and the checklist hide
//  the tab bar so their bottom search field (and the picker's Review button)
//  own that edge, and the tab bar returns when they pop.
//

import XCTest

@MainActor
final class TabNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    func testTabsShowTheirRootScreens() {
        launch()
        capture("tabs-runs")

        tab("tab-events", index: 1).tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))
        capture("tabs-events")

        tab("tab-dashboard", index: 2).tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
        capture("tabs-dashboard")

        tab("tab-runs", index: 0).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
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

    /// iPhone tab buttons can drop a SwiftUI `Tab`'s accessibility identifier on
    /// iOS 26, so fall back to the button's position in the tab bar.
    private func tab(_ identifier: String, index: Int) -> XCUIElement {
        let byIdentifier = app.tabBars.buttons[identifier]
        return byIdentifier.exists ? byIdentifier : app.tabBars.buttons.element(boundBy: index)
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
