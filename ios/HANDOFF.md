# iOS handoff

## Keyboard dismissal (2 October 2026)

- Aaron (build 10): the checklist's "Actual kms" decimal pad had no way off the screen, so
  it hid the bottom of the roster. Three Opus subagents audited every text input. Only the
  two decimal-pad fields (checklist and Add Run) were blocking; the rest have a Return key.
- Fix, following the Guest* screens' pattern: `.scrollDismissesKeyboard(.immediately)` plus a
  keyboard-toolbar Done button gated on `@FocusState` (`actual-km-keyboard-done`,
  `new-run-km-keyboard-done`). Settings and Add-as-member also got scroll-to-dismiss.
- Add Run bound kilometres through `TextField(value:format:)`, which commits only when
  editing ends. With no exit it sent `nil`. It now binds text and parses through the shared
  `DistanceText` (the checklist's parser, moved to the kit).
- `docs/solutions/ui-bugs/decimal-pad-fields-need-done-and-scroll-dismiss.md` has the rule.
- A malformed distance ("8..2") used to parse to nil, which the checklist treated as "no
  opinion" and silently kept the sheet value. `DistanceText.isMalformed` now blocks Confirm and
  Add, shows "Enter the kilometres as one number, such as 8.2." under the field
  (`actual-km-error`, `new-run-km-error`), and `confirm()` throws `ChecklistError.malformedDistance`.
  Blank text still means "no opinion".
- `DistanceText.format` is pinned to `en_US_POSIX` with no grouping, so the seeded field text
  always round-trips through `parse`; `parse` rejects `nan` and `inf`. The Add Run form state
  is `AddRunDraft` in the kit (`canAdd`, `request`), with unit tests.

## Audit fixes, waves 1 and 2 (2 October 2026)

- Plan: `docs/plans/2026-10-02-002-fix-ios-skill-audit-findings-plan.md`. Rollback tag
  `checkpoint-2026-10-02-before-audit-fixes`. Each package is one merge commit:
  P2 `e841a88` (SwiftUI and view models), P1 `7321a44` (shared sync), P3 `7ad1857` (test
  hygiene), P5a `05b82e5` (accessibility mechanics and copy), P4 `3ea2079` (drain and
  background), plus small follow-up commits for test expectations the packages changed.
- Found during integration, fixed in `00cb904`: the first dictation on a fresh install
  crashed in `SpeechService.requestAuthorization`. The permission callback was formed inside
  the `@MainActor` class, so it was inferred main-actor isolated and trapped on the
  permission service's background queue. Same class as the audio-tap finding, one function
  away. Reset the simulator's speech and microphone privacy to reproduce.
- Decisions: checklist rows keep the button trait and not the toggle trait, because XCUITest
  files a toggle-trait element as a switch and six test files look rows up as buttons; the
  row value carries "Checked" / "Not checked" and the provenance ("Checked, Voice").
- Product observation, not changed: on a fresh unrecorded run the draft seeds its distance
  from the approx km, so Confirm is enabled before anyone is checked and confirming writes
  the approx value as actual.
- Verification after each merge on iPhone 17 Pro (iOS 26.5): full kit target (477 tests,
  66 suites after P4), the package's UI suites, and a five-iteration kit run after P3.
  One simulator at a time: CoreSimulatorService crashed nineteen times under three
  parallel boots and needed a Mac restart.
- Still to come (wave 3): P5b colour and contrast with a review page for Colin, P6 platform
  details and dead code, P7 predicates and test-file splits; then P8 and P9.

## Audit fixes, waves 3 and 4 (2 October 2026)

- Merges, one per package: P7 `8ee9b74` (one outstanding-submission predicate, cache rows
  fetched by their unique key, the three test files over 500 lines split by test group),
  P6 `968b39e` (loggers that never log the secret, a MetricKit subscriber, an ephemeral session
  with a 30 s timeout, intents with more phrases, routes that expire after ten minutes,
  negative distances rejected, a season-bounded date picker, dead FoundationModels branches
  removed), P3b `b88b0eb` (MetricKit registered, a Siri and Shortcuts row, the reminders toggle
  disabled while it updates, 44 pt accent swatches, error and success messages as primary text
  with a coloured symbol, "Merge:" and "Overwrite:" labels, UI-test fixtures compiled only in
  Debug with a Release stub), P8 `5fc1b6d` (one `SyncBanner` for the four view models,
  predicate fetches in the sync files, `SheetState.run(matching:)` identity first,
  `SharedReadAction`, `deleteSecret` on the secret-store protocol), P9 `d954d8f` (a store
  that cannot open is set aside with its sidecars and never deleted, a one-time notice says
  so, `AttendanceSchemaV1` behind a one-schema migration plan, the container names its App
  Group and turns CloudKit off; the notice copy in `Views/StoreRecoveryNotice.swift` is a
  default for Colin to read).
- Follow-up commits on the branch: `7847721` deadline-based `waitForPhase`; `dd670ed` a
  run-matching expectation (date and name beat the saved row index); `67ae448` unfiltered
  guest-detail queries and the "all-time runs" wording; `b76d2bb` the stored predicate.
- Found during integration: the guest history screen froze at full CPU and two UI tests timed
  out evaluating the tree once the promotion screen was pushed. Bisecting by package merge on
  the single test (P4, P6, P3b pass; P8 fails) put it in P8's filtered `@Query` on
  `GuestDetailView`. The screen is back to four unfiltered queries (`9c1ed6a`). Home and Outbox
  carry the same predicate without trouble, so the trigger is this screen's shape, not the
  predicate; `b76d2bb` (a stored predicate instead of a computed one) is hygiene and did not
  change the outcome, whatever its message says. Solution note:
  `docs/solutions/ui-bugs/filtered-query-froze-the-guest-detail-screen.md`.
- Decisions: `GuestDetailView` keeps all four queries unfiltered and filters in memory. A
  submission whose run identity is gone no longer falls back to date and name (P8, by design:
  the engine refuses that row anyway). Checklist rows keep the button trait only (see waves 1
  and 2). The scratch worktree `.claude/worktrees/bisect` (detached) can be removed.
- P5b colour and contrast is committed on `fix/p5b-colour` (`3913817`) and not merged. Colin
  reviews `review/contrast/index.html` first: before and after, Runs and Dashboard, the four
  accents, light and dark, default and AXXXL type. `AccentSurface.swift` darkens an accent in
  linear light to luminance 0.17 (top) and 0.11 (bottom) so white text reaches 4.77:1 or
  better; the orange tiles become dark amber. The page is generated by
  `ios/Tools/contrast-review.sh <UDID> <app> before|after` and checked by
  `ios/Tools/contrast-check.py`.
- Verification on iPhone 17 Pro (iOS 26.5): kit 487 tests in 69 suites on the P8 head with the
  guest detail fix, and 489 after P9; the package UI suites after each merge (28 guest, home and
  outbox tests on the fixed head; TabNavigation, SetupLink and ChecklistKeyboard after P9, all
  green). Final pass on `6c84589`: a Release build with `CODE_SIGNING_ALLOWED=NO` succeeds, and
  every UI suite passes together (71 tests, the opt-in screen tour skipped, 21 minutes).
- Integration lessons: gate a queued job on the previous process's exit (`kill -0 <pid>`),
  never on a text marker that another step can echo. One overlapped run voided 34 of 35 UI
  tests and had to be redone. `simctl openurl` on the custom scheme raises an "Open in FCTC?"
  alert that no script can answer, so the review page captures Runs and Dashboard only. Only
  the Runs screen fills the season cache, so a `-ui-tab dashboard` launch refreshes once in
  `RootTabView`.

## Skill audit (2 October 2026)

- Seven Opus subagents audited the iOS code read-only, each following a group of third-party
  skills from `twostraws/Swift-Agent-Skills` (SwiftUI, SwiftData, concurrency, testing,
  accessibility, platform, whole codebase). Report:
  `docs/reference/2026-10-02-ios-skill-audit.md`. Full code audit: `review/code-audit/CODE_AUDIT.md`
  (gitignored).
- Cross-cutting theme (four audits): more than one `SyncEngine` can drain the same store
  (runtime, background task, old engine after a Settings swap), and `SyncEngine.swift:253` can
  re-queue another engine's in-flight row. Fix once with one drain owner per process.
- Two likely High logic bugs: `HomeView` calls `recoveryCandidates()` with no argument, which
  resolves to the protocol-extension stub and returns `[]`, so the guest-history reminder never
  appears; and a parked shared submission can only be discarded (Merge and Overwrite throw
  `missingConflictState`).
- Nothing from the audit was fixed except the items that touched this branch's own changes
  (distance locale, Add Run form, test hygiene, a regression test for Aaron's report).
- The skill clones were reviewed but not installed: copying into `~/.claude/skills` is
  self-modification and the permission classifier refused it. Colin installs them.

## Dashboard review branch (28 September 2026)

- Branch `dashboard-review`, pull request cpdis/fctc2025#15. Build 9 is on TestFlight for
  FCTC Internal only; FCTC Friends still have build 8.
- Plan: `docs/plans/2026-09-28-001-feat-dashboard-review-and-ios-dashboard-plan.md`.
  Approved mockups: `docs/reference/2026-09-28-dashboard-mockups/ios.html`.
- One additive schema change (`SharedSheetCache.liveAt`, optional); `GuestMigrationTests`
  opens a real build 8 store. No entitlement or bundle change. The update keeps the sheet
  connection, saved guests and pending attendance.

### Colin's build 9 review (29 September 2026)

- One title row for every tab (`Views/TabHeader.swift`): Runs, Events and Dashboard each hide
  the system bar and draw the same row, so the titles sit at one height.
  `TabNavigationUITests.testTabTitlesShareOneHeight` compares their centres (a List row
  holding only a title takes its identifier, so tops differ while the text lines up).
- Dashboard: no "2026 season" subtitle. A season menu sits where Runs has its gear. It lists
  the live season and each earlier listed season (`DashboardStore.seasons`).
  `store.select(season:)` loads an earlier season through `SyncEngine.seasonSnapshot(year:)`
  (read-only, revalidated once per session) and compares it with
  `previousSeasonSnapshot(before:)`. `LifetimePriors.rebased` keeps all-time totals as today.
  The overlay (unsynced check-ins) stays on the live season.
- The "sheet is offline" banner on first load: the launch refresh had failed, and Retry Now
  only cleared the banner and drained. Now a refresh retries transient failures itself
  (`RetryPolicy.reads`: 3 tries, 1 s and 2 s apart). A cancelled refresh (its view went away)
  sets no banner. A failed refresh says "Could not reach the sheet. Showing the runs saved on
  this phone." Retry Now refreshes after a failed refresh, and so does the app becoming
  active. Without device logs, the exact first failure is unknown; any of these three
  causes now clears itself.
- Events: the Birthdays footer ("Today and the next 30 days") is gone.

### Tabs

- The app root is a Liquid Glass tab bar: Runs · Events · Dashboard
  (`Views/RootTabView.swift`). Each tab has its own navigation path.
- Runs is the old Home without Milestones and Birthdays. The run picker and the checklist
  hide the tab bar; the checklist search is pinned to the bottom bar (U11 spike result).
- Routes (reminder tap, App Intent) are handled at the root. The newest route wins. It
  selects Runs, pops it to root and opens the checklist. An engine swap resets every tab.
- Events (`Views/EventsView.swift`, kit `EventsBoard`): This week, Specials grouped by
  date, Milestones, Birthdays.
- Dashboard (`Views/Dashboard/`): headline with a Runs/Km toggle, Together, On a roll, The
  Wall (card and full scrolling Wall), Vs last year, Every run, Leaderboard, Run log, and a
  runner screen (stats, club-day calendar, per-weekday bars, next milestone).
- The look stays Reminders: system colours, the user's accent, SF Pro, numbers in SF Pro
  Rounded bold. The checklist streak reads "N club days in a row".

### Dashboard data flow

```text
@Query rows ──> ActiveSeason.fingerprint ──changed──> DashboardStore.update
                                                        │
  EffectiveRuns (cached season + outbox) ───────────────┤
  LifetimePriors (lifetime totals before this season) ──┼──> DashboardModel ──> cards
  previous-season snapshot (read-only, fetched once) ───┘
```

- `ActiveSeason` (app target) reads the active season's cache once per data change. Events
  reads the same inputs.
- The Wall grid (card and full screen) is one SwiftUI `Canvas` (`WallGrid`), three fills per
  draw. Swift Charts drew one `RectangleMark` per cell and cost ~550 ms of main thread per
  open or sort at a full season (30 runners by 118 runs). VoiceOver reads each runner from the
  names column; the grid is one summary element (`wall-grid`).
- A legacy outbox row overlays only the run it was queued against: row index, date and run
  text must all match (`EffectiveRuns.writes`, the same check as `SheetState.satisfies`).
- `EffectiveRuns` applies queued, in-flight and confirmed-but-unrefreshed shared rows in
  creation order, with each endpoint's own write path. The headline shows "Includes N
  unsynced" when it applied any.
- `DashboardStore` rebuilds `DashboardModel` only when the fingerprint changes. It asks
  `SyncEngine.previousSeasonSnapshot()` after each data change, once the live season is
  cached, and rebuilds only when the answer changed. The engine fetches last season at most
  once per app session (a cached row then answers without a request, and serves offline).
  The snapshot upserts only last season's `SharedSheetCache` row. It never reconciles,
  never sets `latestState` and never reschedules reminders. Each answer belongs to one
  live season: when the live season changes, the store drops it (and any answer in flight)
  and asks again. Legacy endpoints return nil, and the Vs last year card is hidden. A
  failed first fetch with nothing cached shows "Last season not downloaded".
- A shared cache row's `refreshedAt` is when its request started. A confirmed shared write
  stays in the overlay until a refresh requested after the confirmation lands.
- On a cold launch, the engine and the app pick the season the last live refresh returned
  (`SharedSheetCache.liveAt`, read by `SharedSheetCache.live`). Neither the snapshot row nor
  a future tab opened in Guest recovery can become the season new runs write to. Before any
  live refresh has stamped a row, the highest year wins.

### Tests

- Kit: 427 tests pass. New suites: `RunLabelTests`, `ClubDaysTests`, `DashboardModelTests`,
  `ParityFixtureTests`, `WritePathCharacterizationTests`, `EffectiveRunsTests`,
  `SeasonSnapshotTests`, `EventsBoardTests`, `DashboardStoreTests`.
- Parity: `ParityFixtureTests` reads `fixtures/attendance/parity/<season>.json`, the files the
  web writes with `scripts/build-parity-fixtures.js`. For every golden run it checks the
  `RunLabel` parse, then totals, member-km, club days, current and best streaks and the
  milestone shortlist. A rule change on either stack fails one side until both match.
- UI: 60 pass, 1 skipped (the opt-in screen tour). New: `TabNavigationUITests` (11),
  `DashboardUITests` (6), and 3 Events cases in `AttendanceSummaryUITests`.
- New UI-test launch flags: `-ui-events`, `-ui-dashboard`, `-ui-last-season-offline`. New
  hooks: `fctc-attendance://ui-test/route/today-checklist`, `/route/missing-run`,
  `/swap-engine`, `/swap-engine/today-run`. `-ui-events` pins today to Mon 21 Sep 2026, 18:00
  Perth. The README section "UI tests and the screen tour" describes them. Run UI
  tests with `-collect-test-diagnostics never`.

### Known follow-ups

- Historic navigation sets `latestState` to an older season. A warm engine's `addRun` or
  `addMember` could then target it (pre-existing).
- `CatchUpPlanner` still reads cached runs, so a past run recorded offline can be offered
  again until the sync lands.
- Provisional guest ids can overcount +1s by one until the next refresh. An in-flight refresh
  can race the overlay.
- On a legacy endpoint, a cold launch can undercount lifetime priors by one until the first
  refresh (pre-existing).
- The screen tour uses the legacy fake without `-ui-events` or `-ui-dashboard`, so its Events
  and Dashboard shots are sparse.
- Tie order sorts by UTF-16 on iOS and by `localeCompare` on the web (display order only).
- Behaviour changes to call out in the notes: a route switches to Runs at once, and scanning
  a setup code in Settings returns to the Runs root and drops a reminder still waiting for
  the old sheet.
- Profiled 2026-09-29 (Release, iPhone 17 Pro simulator, `-ui-dashboard-full`, macOS
  `sample`): first Dashboard open 290 ms of main thread (was 667 ms), full Wall open under
  10 ms (was ~555 ms), full Wall sort 119 ms. The README has the method. Hitches needs a
  device; profile build 9 on a phone once.

### Private TestFlight build 10 (29 September 2026)

- Version 0.1.0 build 10 from `ios-review-round` (3a7e3c7), the head of pull request
  cpdis/fctc2025#16: the build 9 review round (tab header, season menu, self-healing refresh
  banner, Events Birthdays footer). No schema change since build 9.
- Build `393a61f8-eb63-4a9d-8865-d74eca0c7c22` is VALID and `IN_BETA_TESTING` for FCTC
  Internal only. External state `READY_FOR_BETA_SUBMISSION`: FCTC Friends and External have no
  access. The en-AU notes match `ios/testflight-build-10.txt` (read back).
- Verification: iOS kit 437, iOS UI 63 run (62 passed, 1 skipped screen tour), web Vitest 506.

### Private TestFlight build 9 (29 September 2026)

- Version 0.1.0 build 9 from `dashboard-review` (446e24c), the head of pull request
  cpdis/fctc2025#15. Archive signed with Apple Distribution; app and share extension
  report 0.1.0 (9).
- Build `7b3d2ace-d0f9-4b29-b648-d8e8aa5d742a` is VALID. Internal state is
  `IN_BETA_TESTING`, and only FCTC Internal (Colin's two accounts) has it. External
  state is `READY_FOR_BETA_SUBMISSION`, so FCTC Friends and FCTC External have no access.
- The en-AU notes match `ios/testflight-build-9.txt` (read back from App Store Connect).
  Set with `testflight-notes.py --build 9 --file ios/testflight-build-9.txt`; the script
  now takes an exact build and attaches external groups only when named with `--group`.
- Upgrade: build 9 adds `SharedSheetCache.liveAt`. `GuestMigrationTests` opens a real build 8
  store (`fixtures/attendance/guests/build8-shared.store`) in place, so the update keeps the
  sheet connection, cache, saved guests and pending attendance.
- Apps Script was already live with the matching rules (deployment @5).
- To release to Aaron and Grant later: `python3 ios/Tools/testflight-notes.py --build 9
  --file ios/testflight-build-9.txt --group "FCTC Friends"`, then submit for Beta App Review if
  asked. Rewrite the notes for them first: these say "Private build for Colin".
- Verification: web Vitest 506, Apps Script 279, iOS kit 431, iOS UI 61 run (60 passed,
  1 skipped screen tour), 0 failed.

## Private TestFlight build 8 (28 September 2026)

- Version 0.1.0 build 8 from `release/testflight-build-7` (5858adb). It adds the
  post-build-7 fixes: standard push from the Home tiles (zoom removed), a 44 pt
  Settings gear, run status beside the date, and Review in the bottom toolbar
  with search.
- Build `ed201c2a-58b6-4c09-b71f-4095b6f25557` is VALID. It went to FCTC Internal
  first, then Colin released it to FCTC Friends (Aaron and Grant). Beta App Review
  is APPROVED; internal and external states are both `IN_BETA_TESTING`, with
  automatic tester notification. FCTC External has no access.
- The notes were rewritten for Aaron and Grant to cover every change since
  build 6, their last build. They match `ios/testflight-build-8.txt`.
- Verification: 365 tests, 364 passed, 1 skipped (screen tour), 0 failed. Archive
  signed with Apple Distribution; app and share extension report 0.1.0 (8).

## Private TestFlight build 7 (28 September 2026)

- Version 0.1.0 build 7, built from local branch `release/testflight-build-7`.
  It merges `ui-refinements` with `fix/discarded-submission-requeue`,
  `fix/name-match-false-positives` and `fix/setup-link-deployment-id`.
  Landed on `main` by pull request on 28 September 2026.
- Build `dec0d81b-9b35-4828-9785-749570667a25` is VALID. Internal state is
  `IN_BETA_TESTING`, and only FCTC Internal (Colin's two accounts) has it.
  External state is `READY_FOR_BETA_SUBMISSION`, so FCTC Friends has no access.
- Notes were set on build 7 by number, not by `testflight-notes.py`. That script
  attaches every build to FCTC Friends and picks the latest upload, not an exact
  build. The en-AU notes match `ios/testflight-build-7.txt`.
- No schema, config-storage, entitlement or bundle change, so the update keeps the
  sheet connection, saved guests and pending attendance.
- Verification: 365 tests on the release branch (324 Kit, 41 UI); 364 passed,
  1 skipped (the opt-in screen tour), 0 failed. Archive signed with Apple
  Distribution; app and share extension both report 0.1.0 (7).
- Build fix: `project.yml` now excludes `.impeccable` tool caches. Two caches in one
  target had failed the build with "Multiple commands produce hook.cache.json".

## Shared guests (September 2026)

Work is on `codex/shared-guest-attendance`. The September plan supersedes the old
phone-local guest counter and promotion behavior described below. Colin approved
the private test endpoint and TestFlight distribution to all three testers on
16 September. Production migration and git push remain separate steps.

The server stores shared UUID identities and dated attendance. Promotion converts
the original season rows and keeps all prior run credit. The iOS store preserves
legacy names and queues as recovery evidence. Unknown operation outcomes check
receipts after restart; they do not repeat structural writes.

The shared schema adds caches, provisional identities, operation receipts, and
recovery candidates. A synthetic installed v1 SQLite fixture tests migration.
Guest recovery requires an explicit person, season, run, and existing unnamed slot.
Old `done` records remain ambiguous. Never uninstall the app to fix recovery.

Naming, replacing, or removing a saved guest requires a reviewed overwrite.
Promoted-guest conflict review shows the refreshed attendance and distance before
replacement. An original merge keeps concurrent member and guest attendance.
The Home screen ignores refresh results from a replaced connection.

Offline retry retains the original UUID and digest when completed transport
metrics prove that no request was sent. Missing evidence remains uncertain.
An absent receipt never permits a structural replay. The
[setup helper](../docs/operators/shared-guest-setup.md) follows this same rule
after its durable dispatch marker exists.

Before release, finish the endpoint and two-phone checks, inspect the local
visual review page, and follow the shared guest section of
`docs/plans/packets/U8-release-runbook.md`. Production credentials and sharing
settings are release inputs, not evidence that a local branch has shipped.

### Local verification on 16 September

- Apps Script: 258 tests passed. Dashboard and operator tools: 300 tests passed.
- iOS Kit: 266 tests in 40 suites passed. All 22 UI cases passed across the broad
  run and final rerun. The final 13-case run covers every legacy UI case and the
  final guest correction label.
- The broad run first found two obsolete UI fixtures without endpoint identity.
  Corrected the fake API; retained the production guard and all assertions.
- App and share extension compile for the simulator. The dashboard production
  build passes with its existing large-chunk advisory.
- Small and large iPhone screenshots include largest Dynamic Type. The local
  comparison is `review/shared-guests/index.html` and uses synthetic records.
- All accepted code-review findings are fixed. The review and test receipts
  are listed in `review/shared-guests/evidence.md`.

### Google copy verification on 16 September

Google access is approved for the separate private test script. Both seasons
retain unique run UUIDs. Setup preserved all season cells. An invalid atomic
batch changed no cells. Row insertion retained the original run UUID.
First and middle member insertion preserved original credit, notes and totals.

A fresh promotion converted three 2025 runs and eight 2026 runs into eleven
member marks and eleven lifetime runs. Existing credit, notes, headcounts and
distances stayed unchanged. Saved receipts resolved each interrupted response
without repeating structural writes.
Two independent drafts from the same old revision retained both named guests.
Each guest had one confirmed run after receipt recovery. Two overlapping Google
executions also proved that a held script lock returns `busy` without a partial
operation. Missing and invalid secrets returned no snapshot data.
The real before/after snapshots passed the CSV serializer, dashboard parser,
and milestone loader. All original member totals, run headcounts and distances
matched. Three synthetic promoted members each retained eleven runs. Repeating
the snapshot changed no CSV or timestamp.

Copy testing fixed the journal size, row metadata search, omitted sheet ID zero,
and open-ended formula range handling. The promotion guard also checks each
existing member's calculated summaries at their new column positions. XLSX exports expand those ranges, so
formula verification must also inspect Google's original formula text.

**Remaining release checks:** Verify the physical phones with their preserved
installed stores. Retain phone backups and reconcile their candidates before
any real promotion. Production migration, workflow cutover and push remain
outside the private TestFlight release. Server checks do not prove installed
phone recovery.

### Private TestFlight release on 16 September

- Prepared version 0.1.0 build 4 for Colin, Aaron and Grant. The existing internal
  group also contains Colin's second account; its membership stays unchanged.
- Apple approved build `139369ad-1850-4c5f-8c7c-2521d4f1d6d7`. Both internal
  and external states report `IN_BETA_TESTING`. Verified build 4 belongs to
  FCTC Internal and FCTC Friends; automatic tester notification is enabled.
  The saved en-AU test notes match `ios/testflight-build-4.txt` exactly.
- Deployed version 1 of the private copy script. Its web endpoint executes as
  the owner and requires the shared secret. The workbook stays private.
  The published version contains the twelve runtime modules and manifest;
  it omits the verification helper and contains no embedded secret.
- Verified actual HTTP GET refusal, missing/invalid-secret refusal, shared API
  v2 state with no pending operation, and authenticated export of both seasons.
  The production snapshot consumer passed against that deployed HTTP endpoint.
- Archive and upload succeeded. App, share extension and framework signatures
  passed; all three report 0.1.0 (4). Existing compiler warnings remain in voice
  error handling and the share extension's existential spelling.
- The build preserves each installed phone's existing endpoint. Private setup
  requires scanning its code. Codes for all three testers passed Vision decode
  and device-name checks. The private handoff is
  `review/shared-guests/testflight-build4/setup.html` (ignored, never upload).
- What to Test was written before the archive: `ios/testflight-build-4.txt`.
- Code review: skipped (mechanical diff). This release changes the build number
  and release documentation only. Completed feature review receipts and fixes
  are recorded in `review/shared-guests/evidence.md`.

The sections below are historical handoff records, not current test results.

## Review round 2

### Delivered

- Added post-run reminders with permission, cancellation, de-duplication, deep links, and a test seam.
- Added the image share extension and the protected App Group inbox.
- Added catch-up routing, member statistics, guest promotion, and safe merge retry.
- Added App Intents and a testable background outbox drain.
- Added the Home hero, avatars, three specified haptics, shared provenance badges, and consistent empty states.
- Added Kit coverage for the new pure policies and one hero-card UI test.
- Kept the frozen `getState`, `submitAttendance`, `addMember`, and `addRun` actions unchanged.

### Review fixes

- Protected merge retry from concurrent actual-distance changes.
- Kept same-day reminders when their fire time is still in the future.
- Stopped conflict rows from rescheduling background work forever.
- Stopped reminder work after the user disables reminders.
- Reported reminder scheduling failures to Settings.
- Bounded, downsampled, and protected shared images before storage.
- Moved shared-image decoding and PNG work off the main actor.
- Rolled back a failed share batch instead of reporting false success.

### Verification completed here

- Ran `xcodegen generate` successfully.
- Passed `build-for-testing` for `FCTCAttendanceKit` with the required simulator destination and flags.
- Compiled the app, share extension, Kit tests, and 8 UI tests with the generic iOS source gate.
- Used `CODE_SIGNING_ALLOWED=NO` and excluded `Assets.xcassets` only for that source gate.
- Tried the exact `FCTCAttendance` simulator gate. Asset compilation failed because this sandbox has no available simulator runtime.
- Did not boot a simulator or run tests, as instructed.

### Orchestrator actions

1. Run the exact `FCTCAttendance` simulator build gate on a Mac with an available simulator runtime.
2. Run the full Kit suite. Keep the original 164 tests and all new tests green.
3. Run all 8 UI tests, including the Today's Run hero tap-through test.
4. Verify reminder allow, deny, delivery, and notification-tap routing on a device.
5. Verify both App Intents from Shortcuts and Siri suggestions.
6. Verify share import and dismissal from Photos with 1 and 12 screenshots.
7. Verify background outbox drain with a queued offline submission.

### App Group and signing

Create `group.com.cpdis.fctc-attendance` in the Apple Developer portal.
Enable it for `com.cpdis.fctc-attendance` and `com.cpdis.fctc-attendance.share`.
Regenerate both provisioning profiles after the capability change.

The simulator needs both targets installed with the same App Group entitlement.
TestFlight needs both signed profiles to contain the App Group.
The share extension cannot exchange files when either profile is missing the group.

### Colin actions

1. Set the development team for both targets.
2. Complete the App Group portal and profile steps above.
3. Test the signed share extension before the first TestFlight upload.
4. Confirm reminder preview text is acceptable on the lock screen.

### Intended commit if this worktree cannot write Git metadata

```text
feat(attendance): add review round two

Add reminders, sharing, catch-up, intents, and background sync.
Refine the review UI and conflict recovery with tested Kit seams.

Co-authored-by: Codex
```

### Remaining limits

- Signed App Group behavior needs a simulator or physical-device check.
- Background task timing remains controlled by iOS.
- The external review peer could not authenticate in this sandbox. Local review and independent validation completed.
- This sandbox cannot write Colin's Obsidian daily worknote outside the worktree.
