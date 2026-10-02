---
title: Fix the iOS Skill Audit Findings - Plan
type: fix
date: 2026-10-02
topic: ios-skill-audit-fixes
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: docs/reference/2026-10-02-ios-skill-audit.md
execution: code
---

# Fix the iOS Skill Audit Findings - Plan

## Goal Capsule

- **Objective:** Fix every audit finding that a second, independent pass confirmed from source, in
  file-disjoint packages, each with tests, so the branch can be reviewed and rolled back one
  package at a time.
- **Product authority:** Colin. Colour and copy changes need his sign-off on screenshots. Two
  product choices are made here as defaults and flagged: stale App Intent routes expire after
  ten minutes; a store that cannot open is moved aside (never deleted) and the app shows a notice.
- **Rollback point:** tag `checkpoint-2026-10-02-before-audit-fixes` (commit `bc9aaf5`). Each
  package is one merge commit on this branch.
- **Execution profile:** Agents work in their own git worktrees on their own simulators and
  commit on their own branches. Packages in one wave touch disjoint files. The integrator merges
  each branch, runs the full kit suite and the affected UI tests on iPhone 17 Pro (iOS 26.5), and
  only then starts the next wave. Opus 5.5 takes design and cross-cutting work; Sonnet 5.5 takes
  packages that are small, mechanical and fully specified.
- **Stop conditions:** Stop and ask Colin before any push, before changing the SwiftData schema
  beyond adding a versioned schema for the current models, and if a package needs a file outside
  its list.
- **Tail ownership:** The integrator updates `ios/HANDOFF.md`, the README where behaviour changes,
  and the worknote. Colin ships the next TestFlight build.

---

## Verification result

Seven Opus agents re-derived every finding from source at the checkpoint, each with the installed
skill for its area. Counts over the 106 original findings plus 9 new ones:

| Verdict | Count | Notes |
|---|---|---|
| Confirmed | 83 | includes the ones downgraded to Low |
| Fixed by the checkpoint commit | 4 | TEST-1, TEST-4, TEST-7, TEST-8 partially; PLAT-15, CA-19 |
| Refuted | 5 | SD-7, UI-14, CC-12, CA-30, A11Y-9 in part |
| Duplicates | 6 | UI-7, UI-8, CA-1, CA-8, SD-1/CC-2/PLAT-2 are one theme |
| Needs a device | 8 | listed under Runtime checks |
| New | 9 | SD-NEW-1, CC-NEW-1, UI-NEW-1, UI-NEW-2, A11Y-NEW-1, A11Y-NEW-2, PLAT-NEW-1, CA-NEW-1, CA-NEW-2 |

Compiler proof for the top bug (CA-9): a protocol requirement `f(x:)` with an extension
`f(x: Int = 0)`, called on `any P` with no argument, prints the extension body, not the witness.
`HomeView` calls `recoveryCandidates()` with no argument, so the recovery reminder never renders.

---

## Packages

Build recipe for every package (run inside the package's worktree):

```bash
cd ios && xcodegen generate
xcrun simctl boot <UDID> 2>/dev/null; xcrun simctl bootstatus <UDID> -b
xcodebuild build-for-testing -project FCTCAttendance.xcodeproj -scheme FCTCAttendance -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath DerivedData -quiet
xcodebuild test-without-building -project FCTCAttendance.xcodeproj -scheme FCTCAttendance -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath DerivedData -only-testing:FCTCAttendanceKitTests
```

Rules for every package: edit only the files listed; keep files under 500 lines; comment new
code in detail but keep the comments short; user-facing copy in short plain sentences; never
run `rm -rf` (a hook refuses the whole command); never push; commit with a Conventional Commits
summary of 50 characters or fewer, a body of what and why, and the trailer
`Co-authored-by: Claude Code`.

### Wave 1

#### P1 Shared sync correctness (Opus, simulator iPhone 17 Pro Max)

Files: `ios/FCTCAttendanceKit/Services/SharedAttendanceSync.swift`, `GuestOperationSync.swift`,
`SharedGuestSync.swift`, `GuestRecoverySync.swift`, `SyncEngine.swift` (only `resolveConflict`
and the `conflictState` guard), a new `OutboxFailure.swift`, tests `SharedGuestSyncTests.swift`,
`SyncEngineTests.swift`, `GuestOperationSyncTests` if new.

- **CA-10 + CA-NEW-1 (High).** `parkForReview` stores no snapshot, so Merge and Overwrite on a
  parked shared row throw `missingConflictState` (`SyncEngine.swift` guard before the shared
  branch). Fix: for shared rows resolve with `conflicted.conflictState ?? (try requireSharedState())`;
  `resolveSharedConflict` already checks the run identity against that state. Cover the two other
  no-snapshot paths: a `SharedGuestConflict` with `state == nil` and `identity_ambiguous`. Test:
  park, then merge, then assert a queued replacement.
- **CA-11 + CA-NEW-2 + CA-27 (Medium).** Every classifying branch requires `attemptedDispatch`,
  so a pre-dispatch `badPayload`, decode error or receipt-digest mismatch re-queues forever, and
  on the guest queue the head blocks every later operation. Fix: one shared `OutboxFailure`
  classifier used by both files; pre-dispatch deterministic errors set `.rejected` for guest rows
  and `parkForReview` for shared rows. Test: a digest mismatch parks, and a later guest operation
  still drains.
- **CA-12 (Medium).** Five methods call `drainGuestOperation(id:)` directly
  (`SharedGuestSync.swift`, `GuestOperationSync.swift`, `GuestRecoverySync.swift`), bypassing the
  head-blocks-newer order. Fix: call `await drain()` as `replaceGuestRename` does; callers that
  need a result handle "pending".
- **CA-13 (Low).** Shared conflict replacement drops `deviceName`, never calls `clearConflict()`
  or clears `lastError` on the old row. Fix: match the legacy path.
- **CC-3 + SD-NEW-1 + SD-4 (Medium).** Clock reads suspend between a guard and its mutation
  (`resolveConflict`, `resolveSharedConflict`, `SharedAttendanceSync` lines that set
  `.inFlight` then `await clock.now()` before saving). Fix: read `let now = await clock.now()`
  first and pass it down, as `replacePromotedGuestSubmission` does. Test: a `TickingClock` whose
  `now()` suspends; call `resolveConflict` twice concurrently; assert one replacement row and one
  `conflictNotFound` throw.
- **TEST-5 tests.** Parameterised `StubTransport` tests over `pending_verification` and
  `pending_operation` with own, foreign and nil operation ids; the `pendingOperationId` gate; the
  `.pending` attendance receipt; `busy` after dispatch; a non-retryable park. Rename the existing
  "pre-dispatch" `bad_secret` test, which is post-dispatch.

Acceptance: full kit suite passes; new tests fail before the fix and pass after (show the
before run for CA-10 and CC-3).

#### P2 SwiftUI and view-model correctness (Opus, simulator iPhone 17)

Files: `ios/FCTCAttendance/Views/HomeView.swift`, `HomeComponents.swift`, `VoiceEntryView.swift`,
`ChecklistView.swift`, `OutboxView.swift`, `RootTabView.swift`, `RunPickerView.swift`,
`SettingsView.swift`, `ProposalTriageView.swift`, `EventsView.swift`, `Dashboard/DashboardView.swift`;
kit `ViewModels/ChecklistViewModel.swift`, `VoiceEntryViewModel.swift`, `OutboxViewModel.swift`,
`RunPickerViewModel.swift`, `SettingsViewModel.swift`, `Services/SharedSyncTypes.swift`,
`Services/SpeechService.swift`; tests `ViewModelTests.swift`, `VoiceEntryTests.swift`, UI tests.

- **CA-9 + CA-29 minimal (High).** Pass `includeDismissed: false` at both `HomeView` call sites
  and remove the default arguments from the `SharedSyncTypes` extension stubs. UI test: launch
  with `-ui-recovery` and assert `recover-guests-reminder` exists.
- **UI-1 (High).** `VoiceEntryView.addPerson` returns before the add runs and shares
  `quickAddName`, so two "Add as new person" picks lose one name. Fix: `commitQuickAdd(name:)` in
  the kit (no side channel), `addPerson` becomes `async throws` and awaits it, then
  `uncheckMember`; delete `addPersonError`, its alert and binding (triage shows
  `applyErrorMessage`). Share the helper with `ChecklistView.addScreenshotPerson`. Test: two
  names through the view model path both reach the roster.
- **CC-13 (Medium).** On a failed add the restore of `draft.guests` and `plusOnesOverride` from
  pre-await copies destroys edits made during the request. Fix: undo only the added check and
  the roster name.
- **CC-5 + CC-NEW-1 (Medium).** The parse task is not stored, `parseTranscript` cancels the
  task it runs in, and nothing is re-checked after the await. Fix: cancel the fallback in
  `receive` before parsing, store the parse in `finalizationTask`, and after the await guard
  `!Task.isCancelled, phase == .processing, recordingID == nil`. Test with a fake extractor that
  records `Task.isCancelled`.
- **CC-6 (Medium).** The `installTap` block is formed in a `@MainActor` method and the SDK marks
  it non-Sendable, so it can be inferred main-actor and trap on the audio thread. Fix: build it
  in a `nonisolated static func` or as `{ @Sendable buffer, _ in … }`. Smoke check: start
  dictation on the simulator and confirm no trap.
- **UI-2 + UI-NEW-2 (High).** "Discard Local Submission" and "Overwrite Sheet" act on one tap.
  Fix: `confirmationDialog` for both: "Discard this attendance?" with "Discard Attendance"
  (destructive) and Cancel; "Overwrite the sheet with this attendance?" with "Overwrite Sheet".
- **UI-3 (Medium).** The shared-screenshot "Dismiss" button has a cancel role but deletes the
  images, and the sheet's cancel also clears the inbox. Fix: "Delete Screenshots" (destructive)
  plus "Not Now" (cancel, does nothing); `onDismiss` only resets `sharedImportURLs`; surface a
  `clear()` failure.
- **UI-NEW-1 (Medium).** `.task` re-runs the entry presentation on every reappear, so a checklist
  opened by the dictation route reopens the voice sheet after each pop. Fix: a
  `didRunEntryPresentation` state guard. UI test: dictation route, cancel, open Guests, go back,
  assert no voice sheet.
- **UI-9 (Medium).** `checkSharedScreenshotInbox` ignores `showingVoiceEntry`, so an offer can
  try to present over the voice sheet. Fix: add the guard.
- **UI-5 (Medium).** Toolbar-action failures render as the last list row. Fix: `.alert` bound to
  the view model's error for Confirm, Apply, Save and Add, plus `.sensoryFeedback(.error)`.
- **CC-4 (Medium).** `isResolving` and `isAddingRun` are set inside the Task. Fix:
  `guard !isResolving` and `guard !isAddingRun` at view-model entry before the first await.
- **CA-16 (Low).** Silent guards in `ChecklistViewModel.confirm` and `SettingsViewModel.save`.
  Fix: set `errorMessage` before each throw.
- **CC-9 + CA-2 (Low).** Loose `Task`s from `onChange`/`onReceive` in `HomeView`,
  `DashboardView`, `ChecklistView`, `RunPickerView`. Fix: `.task(id:)`.
- **UI-15 (Low).** `EventsView` rebuilds its timer publisher each body pass. Fix: a `.task`
  sleep loop gated on `scenePhase == .active`.
- **UI-4 cheap part (Medium).** `HomeComponents` Outbox and Settings links push by destination
  inside a typed path. Fix: `NavigationLink(value: HomeRoute.outbox)` and `.settings`. The full
  route rework is deferred.

Acceptance: full kit suite; `ChecklistKeyboardUITests`, `GuestPickerUITests`,
`AttendanceSummaryUITests`, `FCTCAttendanceUITests` and the new UI tests pass.

#### P3 Test hygiene (Sonnet, simulator iPhone Air)

Files: test targets only.

- **TEST-2.** `.timeLimit(.minutes(1))` on `RunReminderTests`, `BackgroundOutboxDrainTests`,
  `HomeRefreshBindingTests`, `SharedGuestViewModelTests`, `SyncEngineTests`, `ViewModelTests`.
- **TEST-3.** `waitUntil` returns `Bool`; `try #require(await waitUntil { … })` at the
  `replaceEngine` site and a positive spinner check before it. Leave `receiveEvents`.
- **TEST-4 remainder.** `EffectiveRunsTests` builds its date with
  `Calendar(identifier: .gregorian)`, as `AddRunDraftTests` does.
- **TEST-7 remainder.** `GuestNameUITests` and `GuestPickerUITests` tap keyboard Done buttons
  with a wait-first helper (copy `tapKeyboardButton` from `ChecklistKeyboardUITests`).
- **TEST-8 remainder.** `continueAfterFailure = false` in `GuestNameUITests`,
  `GuestPickerUITests`, `SharedGuestUITests`; a named constant for the 110 pt toolbar offset and
  a header comment that the simulator must have the hardware keyboard disconnected.
- **TEST-1 remainder.** The drain predicate matches the full label
  `'Unsynced, 0 submissions'`.
- **TEST-10.** Replace `(any Error).self` with the exact error at the five sites; read each
  code path to name it (`SharedGuestSyncTests` line near 294 is `SheetAPIError.notImplemented`).
- **TEST-11.** `try #require` on the parity member names; a test that lists
  `attendance/parity/*.json` in the fixtures bundle and compares with `seasons`.
- **TEST-13.** `try #require(UserDefaults(suiteName:))` with `defer { removePersistentDomain }`
  in `AppearanceTests`; `defer { try? FileManager.default.removeItem(at:) }` for every temp
  store or directory in `BirthdayTests`, `GuestMigrationTests`, `SharedGuestSyncTests`,
  `UndeliveredOperationTests`, `AttendanceFeatureTests`.
- **SD-10.** `GuestMigrationTests` build-8 test copies the `-wal`/`-shm` sidecars.
- **TEST-9.** Remove `.serialized` from the nine suites (none shares a resource), then run
  `FCTCAttendanceKitTests` with `-test-iterations 5`; if anything flakes, restore
  `.serialized` on that suite with a comment naming the shared resource.

Acceptance: full kit suite five times in a row; the touched UI test files pass.

### Wave 2 (after wave 1 merges)

#### P4 Outbox drain and background (Opus, simulator iPhone 17 Pro Max)

Files: `ios/FCTCAttendance/BackgroundOutboxDrain.swift`, `FCTCAttendanceApp.swift`,
`AppRuntime.swift`; kit `Services/BackgroundOutboxDrain.swift`, `SyncEngine.swift` (drain loop),
`LegacyAttendanceSync.swift`, `SyncTypes.swift`, `AppConfigPersistence.swift`; tests
`SyncEngineTests.swift`, `AttendanceFeatureTests.swift`.

- **CC-2 / SD-1 / PLAT-2 / CA-1 (High).** One drain owner per process. `SyncEngineClient`
  inherits `OutboxDraining`; the factory takes `runtime` and `makeEngine` returns
  `await MainActor.run { runtime.config.isConfigured ? runtime.engine : nil }`; drop the
  background keychain re-read. `AppRuntime.apply` awaits the old engine's drain (a `quiesce()`)
  before the new engine drains. Test: two engines on one on-disk container with
  `SuspendingTransport` send one request and end with one `.done` row and no conflict fields.
- **CC-1 (Medium).** The re-drain runs as `Task { }` in a `defer`, outliving
  `setTaskCompleted`. Fix: `repeat { drainRequested = false; await pass() } while drainRequested
  && !Task.isCancelled` inside `drain()`; no Task in the defer. Test: TEST-6
  `drainRequestedDuringDrainRunsAgain` with `SuspendingTransport`.
- **PLAT-1 (Medium).** Submit the next background request first; set the expiration handler
  before the work; completion behind a once-flag (`Mutex<Bool>`); expiry cancels and completes
  false. Test: an expired task still leaves a scheduled request.
- **CA-14 (Medium).** `BackgroundOutboxStateReader` counts queued and checking
  `PendingGuestOperation` rows too.
- **CC-8 + CA-15 (Low).** The row loop checks `Task.isCancelled` and uses per-row `do/catch`
  with `continue`.
- **PLAT-NEW-1 + PLAT-6 + CA-17 (Medium).** A keychain read error reads as "not configured":
  `load()` throws and drops the endpoint, and a foreground drain on a nil endpoint parks every
  row as `identity_review_required`. Fix: `KeychainStoreError.interactionNotAllowed` (-25308)
  treated as retry later (background completes false and resubmits); `load()` keeps the endpoint
  when only the secret fails; `drain()` returns early when `api.endpointIdentity == nil`; the
  `.active` drain also requires `isConfigured`. Log with `Logger`.
- **CC-10 (Low).** Remove `@unchecked` from the coordinator and the scheduler struct; keep it on
  the `BGTask` wrapper.

Acceptance: full kit suite; `AttendanceSummaryUITests` and `FCTCAttendanceUITests` pass.

#### P5a Accessibility mechanics and copy (Sonnet, simulator iPhone 17)

Files: `ChecklistComponents.swift`, `ChecklistView.swift`, `RunPickerView.swift`,
`ShareViewController.swift`, `HomeComponents.swift`, `Dashboard/DashboardCards.swift`,
`Dashboard/DashboardCharts.swift`, `AttendanceComponents.swift`, `ProposalTriageView.swift`,
`ScreenshotImportView.swift`, `GuestDetailView.swift`, `GuestEditorView.swift`,
`GuestPickerView.swift`, `GuestConflictReviewView.swift`, `HomeView.swift` (strings only),
`OutboxView.swift` (strings only).

- **A11Y-2.** `AccessibilityNotification.Announcement(message).post()` in `.onChange` for the
  malformed-distance and confirm errors, the Add Run error, and after the share sheet renders
  an error. Put the distance error in the field's hint too.
- **A11Y-3.** The check row's value includes the provenance badge ("Checked, Voice"); stats via
  `.accessibilityCustomContent`.
- **A11Y-6.** Drop the "Double-tap to check" hint; `.isToggle` instead of `.isButton`.
- **A11Y-8.** Modality and share glyphs use `.font(.title2.weight(.semibold))` and
  `.accessibilityHidden(true)`.
- **A11Y-9.** `.accessibilityInputLabels` on the Wall link ("Last 5 weeks") and the Add Run
  fields ("Meet", "Approx kms", "Run").
- **A11Y-13.** The spinning sync glyph and the drawOff tick are gated on
  `accessibilityReduceMotion`.
- **A11Y-15.** `accessibilityPerformEscape()` cancels the share sheet when not importing.
- **A11Y-4.** The share sheet content sits in `ViewThatFits(in: .vertical) { content;
  ScrollView { content } }`.
- **A11Y-5.** The distance field widths are `@ScaledMetric(relativeTo: .body)` and the row
  switches to `AnyLayout(VStackLayout)` at accessibility sizes, as `GuestEditorView` does.
- **A11Y-14.** `LeaderRow` switches to a vertical layout at accessibility sizes and hides the bar.
- **A11Y-11 (link and swatch only).** The Wall link gets `.frame(minHeight: 44)` and
  `.contentShape(.rect)`; the accent swatches get a 44 pt row height with `.contentShape(.rect)`.
- **UI-12.** Plurals through `DashboardFormat.runs(_:)` and new `submissions(_:)` /
  `confirmedRuns(_:)` siblings at the listed sites.
- **UI-13.** One word per idea: "Suggested" (not "Proposed" or "Model"), "Uncheck", "Import Poll"
  as the button and "import a poll" in sentences, "km", "Guests"; sentence case for buttons
  inside screens, Title Case for navigation titles; replace em dashes with a colon or a new
  sentence; fix the comma splice.
- **UI-11.** `localizedStandardContains` for both searches; `ContentUnavailableView.search`
  when a search has no results.
- **UI-10.** `.sensoryFeedback(.selection, trigger:)` on a dedicated toggle counter and
  `.sensoryFeedback(.success, trigger:)` on confirm; drop the UIKit generators and the unused
  `import UIKit` lines.

Acceptance: full kit suite; `ChecklistKeyboardUITests`, `AttendanceSummaryUITests`,
`TabNavigationUITests`, `GuestPickerUITests` (including the AccessibilityXXXL variants) pass.

### Wave 3 (after wave 2 merges)

#### P5b Colour, contrast and the Wall (Opus, simulator iPhone 17 Pro Max)

Files: `FCTCAttendanceApp.swift` (accent mapping), kit `AppearanceStore.swift` (comment),
`Dashboard/DashboardCards.swift`, `Dashboard/WallView.swift`, `Dashboard/RunnerView.swift`,
`HomeComponents.swift`, `ChecklistComponents.swift`, `SettingsView.swift`, and red or green
message text in `ChecklistView.swift`, `RunPickerView.swift`, `GuestEditorView.swift`,
`ShareViewController.swift`; a new review page under `review/contrast/`.

- **A11Y-NEW-2.** `AccentChoice.green` maps to the asset `AccentColor` (6.6:1 on white), not the
  system green; fix the false comment in `AppearanceStore`.
- **A11Y-1 + A11Y-NEW-1 + UI-8.** Accent is used for fills only; numbers on cards are
  `.primary`; the headline card and the Home tiles get a darker gradient stop
  (`accent.mix(with: .black, by: 0.35)`) under white text; captions at full-opacity white.
  Target 4.5:1 for text and 3:1 for the 60 pt number on every accent, light and dark.
- **A11Y-7.** The unchecked ring is `.secondary` at full opacity, thicker under increased
  contrast.
- **A11Y-12.** Red and green messages use `.primary` text with a coloured symbol, or a darker
  colour in light mode.
- **A11Y-10a + 10c.** `.accessibilityChartDescriptor` on the Wall (categorical x = run dates, one
  series per runner); a no-op `.accessibilityAction` so VoiceOver's double-tap does not land on
  a random row.
- **Review page.** Before and after screenshots per accent (green, orange, teal, blue) in light
  and dark, at the default size and at AccessibilityXXXL, assembled in one local HTML page.
  Colin reviews it before this package merges.

#### P6 Platform details and small cleanups (Sonnet, simulator iPhone 17)

Files: `AppRouting.swift`, `RootTabView.swift` (route expiry only), `SettingsView.swift`
(`ShortcutsLink`, reminders toggle, secure field), `AppRuntime.swift` (reminders flag),
`FCTCAttendanceApp.swift` (MetricKit), a new `MetricsSubscriber.swift`; kit `SheetAPI.swift`
(session config, redacting conformances, action enum), `AppConfigPersistence.swift`
(`deleteSecret`), `RunPickerViewModel.swift` (month style), `DistanceText.swift`,
`ClubRun.swift` (`sheetString`), `AddRunDraft.swift`, `RunPickerView.swift` (date range),
`ShareViewController.swift` (limit), `SyncTypes.swift` (sleep), `RunReminderService.swift`,
`ModelExtractor.swift`, `PollScreenshotParser.swift`, `ImportedScreenshot.swift`,
`HomeViewModel.swift` and `RunPickerViewModel.swift` (shared `chronological`),
`SharedScreenshotInbox.swift`; matching tests.

- **PLAT-5.** `Logger(subsystem: "com.cpdis.fctc-attendance", category:)` for sync, background
  and network; fix the SpeechService subsystem; log the background submit error and
  `SheetAPIError` cases as `.public`; never the secret.
- **PLAT-7.** An `MXMetricManager` subscriber added in `App.init` that logs
  `jsonRepresentation()`.
- **PLAT-8.** A dedicated `URLSessionConfiguration.ephemeral` with a 30 s request timeout.
- **PLAT-9 / PLAT-11.** `supportedModes = .foreground(.immediate)`; two or three phrases per
  shortcut; `shortcutTileColor`; a `ShortcutsLink()` in Settings.
- **PLAT-10 (default chosen).** Routes carry `createdAt` and are dropped on consume after ten
  minutes.
- **PLAT-12.** Drop `.textContentType(.password)` from the secret field.
- **PLAT-13.** `CustomStringConvertible`, `CustomDebugStringConvertible` and
  `CustomReflectable` on `AppConfig` that redact the secret, with a test.
- **PLAT-14.** `Date.FormatStyle().month(.wide)` for section headers.
- **PLAT-18 (two of three).** `deleteSecret()` instead of `writeSecret("")`; a
  `SharedReadAction` enum. No `…ID` rename.
- **CA-19.** `DistanceText.parse` rejects negative values.
- **CA-24.** The Add Run `DatePicker` is bounded to the season.
- **CA-25.** The share extension uses `SharedScreenshotLimits.maximumImageCount` and tells the
  user how many images were skipped.
- **CA-31 / CA-33 / CA-34.** `ClubDate.sheetString(from:)`; one shared inbox check; one
  `RunSnapshot.chronological`.
- **CA-3 / CA-4 / CA-5 / CA-6 / CC-7 / CC-11.** Remove the dead `FoundationModels` `#else`
  branches and enum cases; `pendingNotificationRequests()`; `Task.sleep(for:)`;
  `Task { @MainActor in }` instead of GCD; replace `Task.detached` with nonisolated async
  functions that check cancellation and cancel the Vision request.
- **UI-6.** `setRunRemindersEnabled` sets the flag first and reconciles after; the toggle is
  disabled while updating.

#### P7 Dead code, predicates and file size (Sonnet, simulator iPhone Air)

Files: `SheetAPI.swift`, `SyncTypes.swift`, `SyncEngine.swift` (`refresh()` only),
`PendingSubmission.swift`, `HomeViewModel.swift`, `ChecklistViewModel.swift`
(`removeGuests(at:)` only), `AttendanceSchema.swift` (`version` only), `SharedGuestSync.swift`
(key lookup only), `OutboxView.swift` and `HomeView.swift` (`@Query` predicate only),
`UITestSupport.swift`, `UITestDashboardFixture.swift`, `UITestSharedGuestAPI.swift`,
`FCTCAttendanceApp.swift` and `ChecklistView.swift` (fixture call sites only), the three test
files over 500 lines.

- **CA-26 / PLAT-17.** Delete the proven-dead symbols: `SheetAPIConfiguration`,
  `init(configuration:)`, `addRun(date:meet:run:approxKm:)`, `UnimplementedSheetAPI`,
  `SubmissionStatus.sending/written/conflicted`, `SyncEngine.refresh()`,
  `UnimplementedSyncEngine.refresh()`, `HomeViewModel.lastSyncMessage`,
  `ChecklistViewModel.removeGuests(at:)`, `AttendanceSchema.version`. Keep `getState()`,
  `dismissProposedName`, `addGuest(name:)`.
- **CA-20.** The three UI-test fixture files go under `#if DEBUG` with a Release stub of
  `UITestSupport` (`isEnabled = false`, nil parser and images) so the five call sites compile;
  prove it with a Release build.
- **SD-8.** `PendingSubmission.outstandingPredicate` used by both `@Query`s.
- **SD-5 (engine half).** `#Predicate { $0.key == key }` with `fetchLimit = 1` for the cache
  key lookups.
- **CA-36.** Split `SyncEngineTests`, `AttendanceFeatureTests` and `ViewModelTests` by suite
  into files under 500 lines, moving whole suites only.

### Wave 4 (after wave 3 merges)

#### P8 Duplication and fetches (Opus, simulator iPhone 17 Pro Max)

Files: the four view models with the `SyncEvent` switch, a new `SyncBanner.swift`, the three
sync files with unfiltered fetches, `OutboxViewModel.swift`, `SyncEngine.swift`
(`run(matching:)`), tests.

- **CA-28.** One `SyncBanner(event:)` helper for the event-to-message switch.
- **CA-22 / SD-5 (views half).** `#Predicate` for the unfiltered fetches; filtered `@Query`s
  where a view only fingerprints.
- **CA-32.** `SheetState.run(matching:)` that prefers the run identity, used by the Outbox view
  model and the engine.

#### P9 SwiftData hardening (Opus, simulator iPhone 17)

Files: `FCTCAttendanceApp.swift`, `Models/AttendanceSchema.swift`, a new recovery view,
`GuestMigrationTests.swift`.

- **SD-3 first.** A failed container open is caught and logged; the store and its sidecars are
  moved aside with a timestamp, never deleted; the app shows a notice that the previous local
  data was set aside and where it is. (Default chosen; Colin may prefer a different screen.)
- **SD-2.** `AttendanceSchemaV1: VersionedSchema` with `Schema.Version(0, 3, 0)` and a
  single-stage `SchemaMigrationPlan`; open with `ModelContainer(for:migrationPlan:configurations:)`;
  open tests against `legacy-v1.store` and `build8-shared.store`.
- **SD-6.** `cloudKitDatabase: .none` and `groupContainer: .identifier("group.com.cpdis.fctc-attendance")`,
  with a test or log line that the store path is unchanged.

---

## Deferred, with reasons

- **PLAT-3** universal links: needs a club domain, hosting for the AASA file and a decision
  from Colin.
- **UI-4** full typed-route rework: large; the cheap part ships in P2.
- **PLAT-4** async keychain store: verified Low (a few milliseconds of IPC).
- **PLAT-18** `…Id` to `…ID` rename: touches `@Model` stored properties, so it is a schema change.
- **A11Y-11** Wall row height: a density design call for Colin.
- **SD-9** indexes, **TEST-14** tags, **TEST-12** mass `== false` rewrite, **CA-37** one
  statement per line, **PLAT-16** `Measurement` formatting, **CA-21** static coders, **CA-23**
  double refresh, **CA-35** shared UI-test helper beyond P3's copies: low value or style only.
- **Refuted:** SD-7, UI-14, CC-12, CA-30, A11Y-9 for "Guests" and the leaderboard rows.

## Runtime checks (integrator, in sequence on iPhone 17 Pro)

1. After each merge: full kit suite; the UI suites named in the package.
2. After P3: the kit suite with `-test-iterations 5`.
3. After P2: dictation smoke on the simulator (CC-6); the three new UI tests.
4. After P7: a Release build with `CODE_SIGNING_ALLOWED=NO`.
5. After P5b: the review page; Colin signs off before merge.
6. Device-only items for Colin's next TestFlight pass: VoiceOver on the checklist rows and the
   Wall, AX5 on the share sheet, Voice Control "Show names", the Passwords save prompt.

## Integration

Each agent works in its own worktree on a branch from this commit, commits there, and reports
the branch name, the worktree path, the files changed and the test runs. The integrator merges
with `git merge --no-ff`, resolves conflicts (expected only in test files touched by two
packages), runs the checks above, and tags nothing until Colin reviews. Rollback of one package
is `git revert -m 1 <merge commit>`; rollback of everything is a reset to the checkpoint tag.
