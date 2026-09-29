# FCTC Dashboard notes

## Session Update - 2026-09-28 (dashboard-review)

### What Was Done
- Plan: `docs/plans/2026-09-28-001-feat-dashboard-review-and-ios-dashboard-plan.md`, built on branch `dashboard-review` (19 commits from `e2d479d`, plus docs).
- Shared rules: only `x` counts as attendance (web parser, Swift kit, Apps Script); run labels normalized with stable run ids; club days per season (2025 Wed/Fri, then Mon/Wed/Fri) drive streaks; golden parity fixtures in `fixtures/attendance/parity/` hold web and iOS to the same numbers.
- Web: every season loads once; runs route by id; the dashboard is rebuilt as the fctc.fun Poster reference (headline, On a roll, Leaderboard, The Wall, Every run, Vs last year, Milestones ahead, Run log). The old charts, Recharts and their utilities are removed. Wrapped is unchanged.
- iOS: Liquid Glass tab bar (Runs · Events · Dashboard). Milestones and Birthdays moved to Events. The Dashboard tab and runner screen are drawn in Swift Charts from `DashboardModel`. Stats read `EffectiveRuns` (cached season plus unsynced check-ins), so they work offline. Last season comes from a read-only snapshot. The checklist streak reads "N club days in a row".
- Docs: README (web and iOS), `apps-script/README.md` redeploy note, `ios/HANDOFF.md` branch section.
- Closed from the earlier review findings: a deferred route no longer blocks later routes (U15); a cold launch no longer sends `addRun` to the last-refreshed season (U14); the checklist streak no longer fetches per render (U13).
- 2026-09-29 review pass (simplify, then a multi-reviewer code review; fixes in 0fe5044, 5cc4996, 29290d2 and the iOS app commit):
  - Web: the run-date rule matches Apps Script's `parseSheetDate` (loose forms such as `Sat 4-Oct`, weekday from the calendar); every dated row takes its id in sheet order; the error screen retries; Google Fonts load only on Wrapped; theme storage survives a throwing localStorage; `formatSigned` rounds before the sign; milestones list only the latest roster.
  - iOS kit: refreshes stamp the request start time; a season rollover resets the Dashboard comparison; last season revalidates once per session; `ClubDate(sheetDate:season:)` is the one sheet-date parser (Runs `scheduledAt`, reminders, guest rows, Dashboard).
  - iOS app: Runs, the run picker and route handling resolve the season cache once per data change (`AppRuntime.activeRunsFingerprint`); an engine swap drops a waiting route; the Events UI test pins "now".

### Current State
- Tests (2026-09-29, after the residual pass): web 506 pass; Apps Script 279 pass; iOS kit and UI counts in the 2026-09-29 worknote; `npm run build` clean; parity fixtures unchanged.
- Apps Script is live: deployment @5 (x-only attendance, strict sheet dates), same Web App URL.
- Not pushed. Not on TestFlight (testers have build 8).
- Review page: `http://localhost:5174/review/dashboard-build/index.html` (gitignored; needs the dev server).

### Next Steps
- [x] cpdis/fctc2025#15 merged (29 September 2026).
- [ ] Review and merge the build 9 review round (`ios-review-round`): one tab header, the Dashboard season menu, the self-healing refresh banner, the Events Birthdays footer and the one-row dashboard header.
- [ ] Review and merge cpdis/fctc-site#1 (the Monday run, Dashboard in the phone header) to publish fctc.fun.
- [ ] TestFlight build 10 with the review round, if Colin wants to try it on his phone.
- [ ] Web dashboard at 320 px: the run log table is wider than the screen (349 px). Small phones only.
- [x] TestFlight build 9 is live for FCTC Internal only (29 September 2026). Release it to FCTC Friends later with `--group "FCTC Friends"`, after rewriting its notes for Aaron and Grant.
- [ ] Rerun the screen tour after U17 in light and dark; the review page's light Runs shot predates U15. Give the tour `-ui-events` and `-ui-dashboard` data.
- [ ] Warm engine: historic navigation sets `latestState` to an older season, so `addRun`/`addMember` could target it.
- [ ] `CatchUpPlanner` reads cached runs, so a past run recorded offline can be offered again.
- [ ] Overlay edges: provisional guest ids can overcount +1s until refresh; in-flight refresh race; legacy cold-launch priors can undercount by one.
- [ ] Web: a keyboard-opened tooltip stays put on scroll (`Tooltip.jsx`); check the All time title ("All / time") on the review page.
- [ ] Profile build 9 on a real phone once (Hitches needs a device). Simulator numbers are in README "UI tests and the screen tour".

### Blockers / Open Questions
- None blocking.
- Behaviour changes (Colin agreed 2026-09-29, for the build 9 notes): a route switches to Runs at once; scanning a setup code in Settings returns to the Runs root and drops a waiting reminder route; Vs last year waits for its once-per-session fetch when online.
- Decided 2026-09-29: the milestone email keeps its rule (no roster filter; an extreme edge case); `dataParser.test.js` stays one file; commit summaries over 50 characters stay (no history rewrite).

## Session Update - 2026-09-28

### What Was Done
- Reviewed the iOS app with three read-only reviewers (sync services, models and view models, app shell). Findings and status are in the 2026-09-28 worknote.
- `ui-refinements`: shared motion vocabulary (`ios/FCTCAttendance/Views/Motion.swift`), press feedback, animated checks, rolling counts, recording pulse, Outbox animations, Settings rings, version footer, live sync spinner in the Outbox (new `SyncEvent.syncActivity`), 44 pt Settings gear, run status beside the date, Review in the bottom toolbar with search. Tile zoom tried and removed.
- Fix branches: `fix/discarded-submission-requeue`, `fix/name-match-false-positives`, `fix/setup-link-deployment-id`.
- `release/testflight-build-7` merges all of the above. `ios/project.yml` excludes `.impeccable` tool caches (they broke the build).
- TestFlight: build 7 (Colin only), then build 8. Build 8 is released to FCTC Internal and FCTC Friends (Aaron and Grant); Beta App Review APPROVED. Records in `ios/HANDOFF.md`.
- Opt-in screen tour: `ios/FCTCAttendanceUITests/ScreenTourUITests.swift` (README has the command).

### Current State
- Build 8 (0.1.0) is live for Colin, Aaron and Grant. Full suite on its commit: 365 tests, 364 passed, 1 skipped (tour).
- Landed on `main` by pull request from `release/testflight-build-7` on 2026-09-28. `ui-refinements` and the three `fix/*` branches were its inputs and are fully merged.
- Before/after review page: `review/ui-refinements/index.html` (gitignored).

### Next Steps
- [x] Land the work: pull request from `release/testflight-build-7` into `main` (2026-09-28).
- [ ] Remove the three agent worktrees under `.claude/worktrees/` (command in the 2026-09-28 worknote; the safety hook blocked it).
- [ ] Open review findings: background-drain cancellation strands unsent rows; another endpoint's guest operation blocks the guest queue; shared `addRun` targets the last-refreshed season; a deferred route blocks later routes; the server writes no receipt for early rejections; per-render SwiftData fetch and JSON decode in `AppRuntime.activeSheetState` and ChecklistView.

### Blockers / Open Questions
- None blocking. Collect Aaron's and Grant's TestFlight feedback on build 8, especially the stricter name matching.
