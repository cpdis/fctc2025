# iOS skill audit, 2 October 2026

Seven read-only audits of the iOS app, each run by an Opus 5.5 subagent following a group of
third-party agent skills from the [Swift Agent Skills](https://github.com/twostraws/Swift-Agent-Skills)
index. The tree audited is branch `claude/ios-keyboard-dismissal-bugs-07a47b` with the
keyboard-dismissal and distance fixes applied. No audit built or ran the app, so every
finding is from source. Confidence is marked per finding: Verified (from source), Likely, or
Speculative. Paths are relative to `ios/`.

The full whole-codebase report (37 findings, §1 to §12) is in `review/code-audit/CODE_AUDIT.md`
(gitignored). The six area reports are condensed below.

## Summary

- **One theme, four audits.** The SwiftData, concurrency, platform and whole-codebase audits
  each found that more than one `SyncEngine` can drain the same store at once: the runtime
  engine, the background-task engine, and an old engine still draining after a Settings
  swap. Each has its own `isDraining` flag and its own `ModelContext`. `SyncEngine.swift:253`
  can reset another engine's in-flight legacy row to `.queued`, so a write can be sent twice.
  Fix once: one drain owner per process (the background coordinator borrows
  `runtime.engine`), and the old engine finishes before the new one drains.
- **Two High logic bugs** (whole-codebase audit, Likely): the Home "Review local guest history"
  reminder can never appear, because `recoveryCandidates()` with no argument resolves to a
  protocol-extension stub that returns `[]`; and a parked shared submission can only be
  discarded, because Merge and Overwrite both throw `missingConflictState`.
- **Two High UX bugs** (SwiftUI audit): `VoiceEntryView.addPerson` returns before the person
  is added, so a triage with two new names loses one; and "Discard Local Submission" deletes
  queued attendance with one tap and no confirmation.
- **Accessibility: no P0, four P1.** Contrast on the accent gradients and accent-coloured
  numbers (about 2.2:1 on green or orange), errors that appear in silence for VoiceOver,
  provenance badges hidden from VoiceOver, and a share sheet that cannot scroll at large text.
- **Fixed in this branch from the audits:** the distance field text is now pinned to one
  locale and rejects `nan`; the Add Run form state moved into the kit (`AddRunDraft`) with
  unit tests; the keyboard UI tests stop on first failure, never swipe for a keyboard button,
  and include the regression test for Aaron's report (type a distance, tap Confirm with the
  keyboard up, read it back).

## Recommended order

1. One drain owner per store, and a structured re-drain instead of `Task { }` in a `defer`
   (concurrency 1 and 2, SwiftData 1, platform 1 and 2, code audit 5).
2. `recoveryCandidates(includeDismissed: false)` at both Home call sites, and remove the
   default arguments from the protocol-extension stubs (code audit 1 and 10).
3. Shared conflicts: store the conflict snapshot when parking, and share one "replace and
   supersede" helper with the legacy path (code audit 2 and 6).
4. `addPerson` as `async throws`, shared with `ChecklistView.addScreenshotPerson` (SwiftUI 1).
5. A confirmation on "Discard Local Submission" (SwiftUI 2) and one intent for the shared
   screenshot "Dismiss" button (SwiftUI 3).
6. Contrast: accent for fills only, numbers in `.primary`, darker headline gradient
   (accessibility 1, SwiftUI 8). Announce errors to VoiceOver (accessibility 2).
7. Background drain: submit the next request first, set the expiration handler before the
   work, count guest operations in `needsDrain` (platform 1, code audit 7).
8. Add `Logger` categories for sync, background and network (platform 5, code audit 8).
9. Pre-dispatch deterministic errors must park, not loop (code audit 3).
10. Delete the dead U1 compatibility code (code audit 11, platform 17).

## SwiftData (skills: swiftdata-pro, swiftdata-expert-skill, swiftdata-testing)

The share extension never opens the store, so cross-process history rules do not apply.
There are no `@Relationship`s.

| # | Sev | Where | Finding | Fix | Conf. |
|---|---|---|---|---|---|
| 1 | High | `BackgroundOutboxDrain.swift:54-59` (app), `AppRuntime.swift:65-69, 137-141`, `FCTCAttendanceApp.swift:78` | Up to three engines share one container, each with its own context and drain guard. | One writer per process; the old engine finishes its drain before the new one starts. | Likely |
| 2 | Med | `Models/AttendanceSchema.swift:13-31` | No `VersionedSchema` or `SchemaMigrationPlan`; `AttendanceSchema.version` is dead. | `AttendanceSchemaV1` plus a single-stage plan; capture a build-10 store fixture before the next schema change. | Verified |
| 3 | Med | `FCTCAttendanceApp.swift:63-66` | A failed store open hits `fatalError` and crash-loops with the outbox unreachable. | Catch, move the store aside with a timestamp, show a recovery screen. | Verified |
| 4 | Med | `SharedAttendanceSync.swift:36-38, 59-67`; `GuestReviewSync.swift:64-65`; `GuestRenameReviewSync.swift:43, 57` | Rows are changed, then `await clock.now()` releases the actor before the save; another call's `rollback()` can discard the dispatch flags. | Read the clock first; save before every `await`. | Likely |
| 5 | Low | `GuestDetailView.swift:9-12`, `ChecklistView.swift:19-25`, `EventsView.swift:32-33`, `DashboardView.swift:44-45`; `SharedGuestSync.swift:14, 24-26, 48-49`; `GuestOperationSync.swift:47, 53, 57`; `GuestRecoverySync.swift:27` | Unfiltered `@Query`s over tables that only grow; engine lookups fetch every row (with `stateData` blobs) then filter in Swift. | `#Predicate` plus `fetchLimit = 1`; filter by endpoint or state; `propertiesToFetch` for fingerprints. | Verified |
| 6 | Low | `FCTCAttendanceApp.swift:44-48` | `.automatic` for `groupContainer` and `cloudKitDatabase`; an iCloud entitlement later would turn on sync against six `.unique` attributes. | `cloudKitDatabase: .none`, explicit group container. | Verified |
| 7 | Low | `GuestDetailView.swift:23-25` | Picks the workbook by newest `refreshedAt`, unlike every other path. | `SharedSheetCache.live(in:endpoint:)`. | Likely |
| 8 | Low | `OutboxView.swift:14`, `HomeView.swift:41` | Predicate hard-codes `"done"`. | Shared `PendingSubmission.outstandingPredicate`. | Verified |
| 9 | Low | `PendingSubmission.swift:30`, `SharedGuestPersistence.swift:89` | No `#Index` on hot predicates. | Optional, together with 2. | Speculative |
| 10 | Low | `GuestMigrationTests.swift:55`; `BirthdayTests.swift:185-253`; `SharedGuestSyncTests.swift:43, 105, 206`; `UndeliveredOperationTests.swift:119` | Build-8 test skips `-wal`/`-shm`; temp stores never deleted. | Copy sidecars; `defer` the cleanup. | Verified |

## Concurrency (skills: swift-concurrency-pro, swift-concurrency, swift-concurrency-expert)

Settings: `SWIFT_VERSION 6.0`, strict concurrency complete, no default isolation. Plain
`nonisolated async` calls still hop off the caller's actor, which finding 3 relies on.

| # | Sev | Where | Finding | Fix | Conf. |
|---|---|---|---|---|---|
| 1 | High | `SyncEngine.swift:228-235`, `LegacyAttendanceSync.swift:19-28`, `SharedAttendanceSync.swift:52` | A successful shared write triggers a second drain pass through `Task { }` in a `defer`; in the background handler it runs after `setTaskCompleted`. | `repeat { … } while drainRequested` inside `drain()`; background engine with `automaticallyDrains: false`. | Verified |
| 2 | High | `BackgroundOutboxDrain.swift:54-60` (app), `AppRuntime.swift:65-69, 135-144`, `SyncEngine.swift:253` | Second engine on the same store; `:253` re-queues another engine's in-flight row. | One drain owner per store. | Likely |
| 3 | Med | `SyncEngine.swift:321, 355, 361-365`; `SharedAttendanceSync.swift:144-148` | Check-then-act across `await clock.now()`: two `resolveConflict` calls can both insert a replacement row. | Read the clock before the guard. | Verified |
| 4 | Med | `OutboxView.swift:437-446`, `OutboxViewModel.swift:63-69`; `RunPickerView.swift:294-300`, `RunPickerViewModel.swift:143-146` | `isResolving` / `isAddingRun` set only after the `Task` starts; a double tap adds the run twice. | Guard before the first `await`, or `Task.immediate`. | Likely |
| 5 | Med | `VoiceEntryViewModel.swift:146-148, 162-179` | Parse task not stored; nothing re-checked after the await, so an old parse can set `.triage` while a new recording runs. | Store in `finalizationTask`; guard after the await. | Verified |
| 6 | Med | `SpeechService.swift:196-198` | The `installTap` closure may be inferred `@MainActor` and trap on the audio thread. | `@Sendable` closure or a `nonisolated static func`. | Speculative |
| 7 | Low | `PollScreenshotParser.swift:47`, `ImportedScreenshot.swift:27, 33`, `ShareViewController.swift:73` | `Task.detached` ignores cancellation; Vision runs each image to the end. | `@concurrent` async functions with `checkCancellation()`. | Verified |
| 8 | Low | `SyncEngine.swift:258-268` | Row loop never checks cancellation. | `if Task.isCancelled { break }`. | Verified |
| 9 | Low | `DashboardView.swift:233`, `HomeView.swift:228, 237-249` | Loose `Task`s from `onChange`/`onReceive`. | `.task(id:)`. | Verified |
| 10 | Low | `BackgroundOutboxDrain.swift:71` (kit), `:13` (app), `SyncTypes.swift:78`, `RequestDeliveryTracker.swift:28`, `AppRouting.swift:19, 34` | `@unchecked Sendable` where plain `Sendable` or `Mutex` would do; `DispatchQueue.main.async`. | Remove `@unchecked`; `Mutex`; `Task { @MainActor in }`. | Verified |
| 11 | Low | `RunReminderService.swift:257-262` | Hand-written continuation; the SDK has `pendingNotificationRequests()`. | Use the async overload. | Verified |
| 12 | Low | `SheetAPI.swift:92, 144` | Actors with only `let` state serialise JSON work. | `final class: Sendable` or structs. | Likely |
| 13 | Low | `ChecklistViewModel.swift:272-288` | Failure path restores pre-await copies, losing edits made during the await. | Undo only the specific change. | Verified |

## SwiftUI and copy (skills: swiftui-pro, swiftui-ui-patterns, swiftui-design-principles, writing-for-interfaces)

| # | Sev | Where | Finding | Fix | Conf. |
|---|---|---|---|---|---|
| 1 | High | `VoiceEntryView.swift:317-328`, `ProposalTriageView.swift:400-406` | `addPerson` returns before the add runs; two new names in one triage lose the first. | `async throws`, shared with `ChecklistView.addScreenshotPerson`. | Likely |
| 2 | High | `OutboxView.swift:380` | One-tap destructive "Discard Local Submission". | `confirmationDialog`. | Verified |
| 3 | Med | `RootTabView.swift:112-114`, `ChecklistView.swift:291-293, 249, 436-439` | "Dismiss" with cancel role deletes shared screenshots; cancel also clears the inbox; error swallowed. | One intent; show the error. | Verified |
| 4 | Med | About 15 `NavigationLink(destination:)` in a typed `[HomeRoute]` stack | Route resets cannot see destination pushes. | `NavigationLink(value:)` and more `HomeRoute` cases. | Verified |
| 5 | Med | `ChecklistView.swift:173-179`, `ProposalTriageView.swift:124-131`, `SettingsView.swift:129-139`, `RunPickerView.swift:272-277` | Toolbar-action errors render as the last list row. | `.alert`, or error first; `.sensoryFeedback(.error)`. | Likely |
| 6 | Med | `SettingsView.swift:92-97`, `DashboardView.swift:95-97`, `GuestEditorView.swift:69-72` | `Binding(get:set:)` whose setter only starts a Task; the toggle snaps back. | `@State` mirror plus `.onChange`. | Verified |
| 7 | Med | `SettingsView.swift:225-238`, `WallView.swift:86` | Hit targets of about 28 pt and 22 pt. | 44 pt frames with `contentShape`. | Likely |
| 8 | Med | `HomeComponents.swift:19-55, 207-232`, `HomeView.swift:268, 288`, `DashboardCards.swift:163-211` | Translucent white on accent gradients; green, orange and teal accents fail 4.5:1. | Foreground per accent or darker gradient stop. | Likely |
| 9 | Med | `ChecklistView.swift:29-36, 223, 247` | Four boolean sheet flags that can conflict. | One `enum ChecklistSheet` with `.sheet(item:)`. | Verified |
| 10 | Low | `ChecklistView.swift:147, 380`, `ProposalTriageView.swift:149` | UIKit feedback generators. | `.sensoryFeedback`; drops `import UIKit`. | Verified |
| 11 | Low | `ChecklistView.swift:328`, `RunPickerView.swift:43-45, 96-107` | `localizedCaseInsensitiveContains`; custom empty search view. | `localizedStandardContains`; `ContentUnavailableView.search`. | Verified |
| 12 | Low | 10 sites | "1 runs", "1 submissions", hand-rolled plural ternaries. | `^[\(n) run](inflect: true)`. | Verified |
| 13 | Low | Copy | "Proposed" vs "Model"; "Untick" vs "Uncheck"; "kms"/"km"/"kilometres"; mixed Title Case and sentence case; em dashes. | A short word list and one capitalisation rule. | Verified |
| 14 | Low | 9 sites | Fixed `.system(size:)` fonts. | Text styles, `@ScaledMetric`, or `Font.scaled(by:)`. | Verified |
| 15 | Low | `AppRouting.swift:34`, `EventsView.swift:73`, `VoiceEntryView.swift:70`, `FCTCAttendanceApp.swift:130` | GCD post; timer rebuilt per body; OK-only alerts. | `Task { @MainActor }`; `.task` loop; `.alert { }`. | Verified |

The audit also noted a deliberate deviation to keep: the text-bound distance fields with
`DistanceText`. The skill's "bind a `Double` with a format" rule is wrong here, because a
formatted binding commits only when focus ends and the decimal pad has no Return key.

## Accessibility (skills: ios-accessibility, swift-accessibility-skill, swiftui-accessibility-auditor, uikit-accessibility-auditor)

No P0. P1 blocks a group of users from a core task; P2 is polish.

| # | Sev | Where | Finding | Fix | Conf. |
|---|---|---|---|---|---|
| 1 | P1 | `DashboardCards.swift:154-211, 331`, `WallView.swift:81`, `RunnerView.swift:65` | White on green or orange accent about 2.2:1; accent numbers on white cards the same. | Accent for fills; numbers in `.primary`; darker headline background. | Verified |
| 2 | P1 | `ChecklistView.swift:131-135, 173-179`, `RunPickerView.swift:262-276`, `ShareViewController.swift:162-167` | Errors appear in silence; no `AccessibilityNotification` anywhere. | Announce on change, or `@AccessibilityFocusState` on the error text. | Verified |
| 3 | P1 | `ChecklistComponents.swift:28-34, 42-45` | `.accessibilityElement(children: .ignore)` drops the provenance badge. | Put the badge in the value. | Verified |
| 4 | P1 | `ShareViewController.swift:148-179` | Bare `VStack` in the extension sheet cannot scroll at AX5. | `ScrollView` or `ViewThatFits`. | Likely |
| 5 | P2 | `ChecklistView.swift:103-113` | Distance field width fixed in points; "8.75" scrolls out of view at AX sizes. | `@ScaledMetric` widths; vertical layout at AX sizes. | Likely |
| 6 | P2 | `ChecklistComponents.swift:44-46` | Hint restates the gesture; redundant `.isButton`. | Drop the hint; `.isToggle`. | Verified |
| 7 | P2 | `ChecklistComponents.swift:106` | Unchecked ring at 0.45 opacity, under 3:1. | Full-opacity `.secondary`. | Likely |
| 8 | P2 | `ChecklistComponents.swift:81-82`, `ShareViewController.swift:150-152` | Decorative glyphs not hidden; fixed sizes. | `.accessibilityHidden(true)`; text styles. | Likely |
| 9 | P2 | `ChecklistView.swift:128`, `DashboardCards.swift:377`, `DashboardCharts.swift:189`, `RunPickerView.swift:250-259` | Labels do not match visible text, so Voice Control "Tap Last 5 weeks" fails. | `.accessibilityInputLabels`; values instead of labels. | Verified |
| 10 | P2 | `WallView.swift:146-173` | Canvas exposes only a summary; streak by colour alone; VoiceOver double-tap lands mid-grid. | `.accessibilityChartDescriptor`; outline for streak cells; check the tap on device. | Verified / Speculative |
| 11 | P2 | `WallView.swift:86`, `DashboardCards.swift:371-378`, `SettingsView.swift:233` | Targets of 22, 20 and 36 pt. | 44 pt. | Verified |
| 12 | P2 | Red footnotes and `.green` success text in light mode | 3.2 to 3.5:1 and 2.2:1. | Darker text, or `.primary` with a coloured symbol. | Verified |
| 13 | P2 | `HomeComponents.swift:211`, `ChecklistComponents.swift:119` | Spinning sync glyph ignores Reduce Motion. | Gate on `reduceMotion`. | Verified |
| 14 | P2 | `DashboardCharts.swift:224-246` | `LeaderRow` truncates names at AX sizes. | Vertical layout at AX sizes. | Likely |
| 15 | P2 | `ShareViewController.swift:13-139` | No escape path while importing. | `accessibilityPerformEscape()`. | Speculative |

Manual checks the audit asks for: VoiceOver on the checklist rows and the "8..2" error; AX5
on the share sheet; Accessibility Inspector contrast per accent in light and dark; grayscale
on the Wall; Voice Control "Show names"; Reduce Motion on sync. No UI test calls
`performAccessibilityAudit()` today; one per tab would catch most of the P2s.

## Platform (skills: app-intents, background-execution, observability, swift-security-expert, swift-format-style, swift-api-design-guidelines)

| # | Sev | Area | Where | Finding | Fix | Conf. |
|---|---|---|---|---|---|---|
| 1 | Med | Background | `BackgroundOutboxDrain.swift:106-133` (kit) | Next request submitted only on success; expiration handler set after the work starts. | `scheduleIfNeeded()` first; handler before the work; idempotent completion. | Verified |
| 2 | Med | Background | `FCTCAttendanceApp.swift:58-62, 78`, `BackgroundOutboxDrain.swift:54-60` (app) | Second engine on the same store. | Borrow `runtime.engine`. | Likely |
| 3 | Med | Security | `project.yml:108-112`, `SetupCodeParser.swift:57-77` | Endpoint and secret travel in a custom-scheme URL; schemes are not exclusive. | Universal link with the payload in the fragment. | Likely |
| 4 | Med | Security | `AppRuntime.swift:63`, `SettingsViewModel.swift:30, 58`, `AppConfigPersistence.swift:39-53` | `SecItem*` calls run synchronously on the main actor. | Keychain store as an `actor`; async load and save. | Verified |
| 5 | Med | Observability | `SyncEngine.swift:269-273`, `BackgroundOutboxDrain.swift:98-133` (kit), `SheetAPI.swift:236-245` | The only `Logger` is in `SpeechService`, with the wrong subsystem; `try? scheduler.submit` hides errors. | `Logger(subsystem: "com.cpdis.fctc-attendance", category:)` for sync, background, network. | Verified |
| 6 | Low | Security | `AppRuntime.swift:63`, `AppConfigPersistence.swift:74-75` | A locked keychain reads as "not configured". | `KeychainStoreError.locked`, retry later. | Likely |
| 7 | Low | Observability | `FCTCAttendanceApp.swift:25-67` | No MetricKit subscriber; no signposts. | `MXMetricManager.shared.add`; `OSSignposter`. | Verified |
| 8 | Low | HTTP | `SheetAPI.swift:96, 101-105` | `URLSession.shared`: 60 s timeout and shared cache; longer than the background budget. | Ephemeral session, 15 to 20 s timeout. | Likely |
| 9 | Low | Intents | `AppRouting.swift:87, 98` | `openAppWhenRun`. | `supportedModes` (iOS 26). | Likely |
| 10 | Low | Intents | `AppRouting.swift:89-103`, `RootTabView.swift:126-134` | `perform()` never fails; a stale route can fire days later. | Return a dialog, or stamp and expire routes. | Verified |
| 11 | Low | Intents | `AppRouting.swift:106-120` | One phrase per shortcut; no tile colour; no `ShortcutsLink`. | Add them. | Verified |
| 12 | Low | Security | `SettingsView.swift:70-71` | `.textContentType(.password)` invites a Passwords save prompt. | Drop it. | Speculative |
| 13 | Low | Security | `SheetAPI.swift:62-74` | `AppConfig` prints `secret` through `description` or `dump`. | Redacting conformances. | Likely |
| 14 | Low | Format | `RunPickerViewModel.swift:100-102, 120` | `DateFormatter("MMMM")` per call. | `Date.FormatStyle().month(.wide)`. | Likely |
| 15 | Low | Format | `DistanceText.swift` | Format in device locale, parse ASCII only. | Fixed in this branch. | Likely |
| 16 | Low | Format | `HomeComponents.swift:39`, `UpcomingSections.swift:37`, `DashboardCards.swift:114-126`, others | Units and plurals built by hand. | `Measurement` styles; inflection. | Verified |
| 17 | Low | API | `SheetAPI.swift:76-77, 163-168, 211-219, 382-396`, `SyncEngine.swift:180-183`, `SyncTypes.swift:178` | Callerless compatibility shims; duplicate protocol requirements. | Delete; one requirement plus an extension default. | Verified |
| 18 | Low | API | `AppConfigPersistence.swift:12-15, 82-89`, `SheetAPI.swift:135` | `writeSecret("")` deletes; string actions; `…Id` casing. | `deleteSecret()`; enum; `…ID`. | Verified |

## Whole codebase (skill: ios-code-audit)

177 files, about 32.5k lines. 37 findings: 2 High, about 14 Medium, the rest Low. The top
items not already listed above:

- **High, Likely.** `HomeView.swift:171, 228` call `recoveryCandidates()` with no argument,
  which resolves to the stub in `SharedSyncTypes.swift:48` and returns `[]`. The reminder
  never appears. No UI test checks `recover-guests-reminder`.
- **High, Likely.** `parkForReview` (`SharedAttendanceSync.swift:125-130`) stores no conflict
  snapshot; Outbox offers Merge and Overwrite that both throw `missingConflictState`.
- **Med, Likely.** Pre-dispatch deterministic errors re-queue forever as "checking saved
  changes" (`SharedAttendanceSync.swift:68-90`, `GuestOperationSync.swift:71-84`).
- **Med, Likely.** Five methods dispatch guest operations directly, breaking the promised
  head-blocks-newer order (`SharedGuestSync.swift:149, 167`, `GuestOperationSync.swift:101, 114`,
  `GuestRecoverySync.swift:55`).
- **Med, Verified.** Shared conflict resolution drops `deviceName` and never calls
  `clearConflict()` (`SharedAttendanceSync.swift:142-149`).
- **Med, Verified.** The background drain counts only `PendingSubmission` rows, not guest
  operations (`BackgroundOutboxDrain.swift:56-68`, kit).
- **Med, Verified.** Protocol extensions give silent stubs for 19 `SyncEngineClient` and 5
  `SheetAPIClient` requirements, which is what made the first High possible.
- **Med, Verified.** About 80 lines of dead U1 compatibility code; the outbox error ladder
  copied in two files; the `SyncEvent` message switch in four view models; four private
  display-distance formatters.
- Lower: an unused `message` binding (`VoiceEntryViewModel.swift:134`); `.prefix(12)` truncates
  shared images silently; dead `#else` branches behind `canImport(FoundationModels)`; about
  760 lines of UI-test fixture code shipping in Release; three test files over 500 lines.

## What the app already does well

Every audit agreed on these, so leave them alone:

- One writer: all SwiftData writes go through `SyncEngine`'s own context with explicit
  `save()`; views only read. No `@Model` object crosses an actor; the engine returns
  Sendable snapshots.
- Persist before dispatch, with receipts, operation IDs, request digests and the
  `RequestDeliveryTracker`, so a crash or cancellation checks rather than resends.
- Real migration rehearsal against captured stores; additive optional fields.
- `@Observable @MainActor AppRuntime`, typed tab paths, routes handled in one place.
- Reduce Motion handled centrally in `Motion.swift`; Swift Charts marks carry labels;
  `AnyLayout`, `@ScaledMetric` and `ViewThatFits` where they matter.
- Keychain item is `AfterFirstUnlockThisDeviceOnly`, every `OSStatus` checked, the secret
  behind a protocol seam with a test that proves it never reaches UserDefaults.
- Tests inject time, control ordering with continuations, use fresh in-memory stores, and
  hold the web and Swift to the same golden parity fixtures.

## Skills used

Reviewed and used from local clones at pinned commits (see the memory note
`swift-agent-skills-review`). Each was scanned for scripts and risky instructions before use;
nothing beyond README install commands turned up. The Claude Code permission classifier
refused to copy them into `~/.claude/skills` (self-modification), so installing them is a
step for Colin. The reviewed clones are in this session's scratchpad under `skills-src/`;
the destination layout is one folder per skill, named after the SKILL.md `name`, with the
twostraws repos installed from their nested `skills/<name>/` copy.

Skill quality notes from the agents: the swiftdata-testing skill makes two claims the agent
judged wrong; two testing skills show a `.timeLimit(.seconds(…))` API that does not exist;
the twostraws and AvdLee skills assume Swift 6.2 while this project is on 6.0.

## Caveats

Static review only. Nothing here was confirmed on a device or by a build. Items marked
Likely or Speculative need a repro before they are treated as bugs, and the contrast ratios
come from standard system colour values, not from a screen measurement.
