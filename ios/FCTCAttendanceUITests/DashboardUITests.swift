//
//  DashboardUITests.swift
//  FCTCAttendanceUITests
//
//  The Dashboard tab (R23–R27) over the `-ui-dashboard` season
//  (`UITestDashboardFixture`): 30 runs, Aaron on a 14 club-day streak, a
//  special Pub Run, last season 52 weeks earlier, and one blank latest row
//  (row 130) left for the offline test to record. The captures named `u17-*`
//  are the review screenshots; run the suite once per appearance.
//

import XCTest

@MainActor
final class DashboardUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The fixture's blank latest club day, which the offline test records.
    private let unrecordedRow = 130

    /// The headline shows the season's runs and flips to km (R23), with last
    /// season compared on the same date.
    func testHeadlineShowsSeasonRunsAndToggle() {
        launch()
        openDashboard()
        let headline = element("headline-value")
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertEqual(headline.value as? String, "30")
        XCTAssertEqual(headline.label, "Runs this season")

        let metric = app.segmentedControls["headline-metric"]
        XCTAssertTrue(metric.buttons["Runs"].isSelected)
        metric.buttons["Km"].tap()
        XCTAssertTrue((headline.value as? String)?.hasSuffix(" km") == true, String(describing: headline.value))
        XCTAssertEqual(headline.label, "Km together this season")
        metric.buttons["Runs"].tap()
        XCTAssertEqual(headline.value as? String, "30")
        XCTAssertTrue(element("headline-comparison").label.contains("by this date"))
        XCTAssertFalse(element("dashboard-unsynced").exists)
        settle()
        capture("u17-dashboard-top")

        // A shared endpoint with two seasons compares them.
        let vs = element("vs-last-year")
        scrollTo(vs)
        XCTAssertTrue(vs.exists)
        settle()
        capture("u17-dashboard-scrolled")

        let log = element("dashboard-run-log")
        scrollTo(log)
        settle()
        capture("u17-dashboard-bottom")
    }

    /// The Wall card's streak leader opens their runner screen (R24, R25).
    func testWallCardStreakLeaderOpensRunnerScreen() {
        launch()
        openDashboard()
        let aaron = element("wall-card-runner-Aaron")
        scrollTo(aaron)
        XCTAssertEqual(aaron.value as? String, "29 runs, streak 14")
        aaron.tap()

        XCTAssertTrue(app.navigationBars["Aaron"].waitForExistence(timeout: 5))
        XCTAssertEqual(element("runner-streak").value as? String, "14")
        XCTAssertEqual(element("runner-runs").value as? String, "29")
        XCTAssertTrue(element("runner-summary").label.hasPrefix("#1 on runs"), element("runner-summary").label)
        settle()
        capture("u17-runner")

        // All time: 147 lifetime runs, 3 short of 150 (KTD12).
        let allTime = element("runner-all-time")
        scrollTo(allTime)
        XCTAssertTrue(allTime.label.contains("3 runs to 150"), allTime.label)
    }

    /// The full Wall opens scrolled to the latest run, and a tapped cell opens
    /// that row's runner.
    func testFullWallOpensAtLatestRun() {
        launch()
        openDashboard()
        let open = element("wall-open")
        scrollTo(open)
        open.tap()
        XCTAssertTrue(app.navigationBars["The Wall"].waitForExistence(timeout: 5))
        settle()

        // The grid scrolls inside the page: it ends at the visible right edge
        // (the latest run) and starts off screen to the left.
        let scroller = app.scrollViews["wall-full"].scrollViews.firstMatch
        XCTAssertTrue(scroller.waitForExistence(timeout: 5))
        let grid = element("wall-grid")
        XCTAssertTrue(grid.exists)
        XCTAssertEqual(grid.frame.maxX, scroller.frame.maxX, accuracy: 2, "The Wall did not open at the latest run")
        XCTAssertLessThan(grid.frame.minX, scroller.frame.minX - 20, "The Wall has no earlier runs to scroll to")
        capture("u17-wall")

        // A cell tap reads the runner from the grid row, level with their name.
        let colName = element("wall-runner-Col").frame
        let tapPoint = CGVector(dx: scroller.frame.maxX - 12, dy: colName.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(tapPoint).tap()
        XCTAssertTrue(app.navigationBars["Col"].waitForExistence(timeout: 5))
        XCTAssertEqual(element("runner-streak").value as? String, "10")
    }

    /// Attendance recorded offline counts at once: the headline and the streak
    /// include it, and the card says so (R26, AE8, KTD11).
    func testOfflineRecordingCountsInHeadlineAndStreak() {
        launch(["-ui-shared-guests", "-ui-dashboard", "-ui-offline"])
        openDashboard()
        XCTAssertTrue(element("headline-value").waitForExistence(timeout: 5))
        XCTAssertEqual(element("headline-value").value as? String, "30")
        XCTAssertTrue((element("on-a-roll").value as? String)?.hasPrefix("Aaron, 14 ") == true)

        app.tab(.runs).tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        tap(app.buttons["home-all-runs"])
        tap(app.buttons["run-row-\(unrecordedRow)"])
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        tap(app.buttons["member-Aaron"])
        app.buttons["confirm-attendance"].tap()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-unsynced"].label.contains("1 submissions"), app.buttons["home-unsynced"].label)

        openDashboard()
        let headline = element("headline-value")
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertEqual(headline.value as? String, "31")
        XCTAssertEqual(element("dashboard-unsynced").label, "Includes 1 unsynced")
        let onARoll = element("on-a-roll")
        XCTAssertTrue((onARoll.value as? String)?.hasPrefix("Aaron, 15 ") == true, String(describing: onARoll.value))
    }

    /// A legacy endpoint has no last season, so Vs last year is hidden.
    func testLegacyEndpointHidesVsLastYear() {
        launch([])
        openDashboard()
        let headline = element("headline-value")
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertEqual(headline.value as? String, "1")
        // Give the (instant) last-season answer time to land before the check.
        settle()
        scrollTo(element("dashboard-run-log"))
        XCTAssertFalse(element("vs-last-year").exists)
        XCTAssertFalse(element("vs-last-year-not-downloaded").exists)
        XCTAssertTrue((element("together").value as? String)?.hasSuffix("Member-km this season") == true)
    }

    /// Offline before last season was ever fetched, the card says so instead
    /// of hiding.
    func testLastSeasonNotDownloadedOffline() {
        launch(["-ui-shared-guests", "-ui-dashboard", "-ui-last-season-offline"])
        openDashboard()
        let missing = element("vs-last-year-not-downloaded")
        scrollTo(missing)
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        XCTAssertEqual(missing.label, "Last season not downloaded")
        XCTAssertFalse(element("vs-last-year").exists)
    }

    // MARK: - Helpers

    /// The shared fake with the dashboard season, unless a test passes its own.
    private func launch(_ fixture: [String] = ["-ui-shared-guests", "-ui-dashboard"]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + fixture
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 8))
    }

    private func openDashboard() {
        app.tab(.dashboard).tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
    }

    /// Any element by identifier: cards and combined rows are not always the
    /// element type their content suggests.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    private func tap(_ element: XCUIElement) {
        scrollTo(element)
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
    }

    /// Lets entrance animations and transitions finish before a capture.
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
