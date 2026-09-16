# iOS handoff

## Shared guests (September 2026)

Work is on `codex/shared-guest-attendance`. The September plan supersedes the old
phone-local guest counter and promotion behavior described below. Deployment,
production migration, push, and TestFlight distribution require separate approval.

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

**Remaining release checks:** Verify the deployed endpoint and both physical
phones with their preserved installed stores. Retain both phone backups and
reconcile their candidates before any real promotion. Production migration,
endpoint deployment, workflow cutover, push and TestFlight remain unapproved.
The browser helper checks server behavior; it does not prove phone transport
or installed-data recovery.

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
