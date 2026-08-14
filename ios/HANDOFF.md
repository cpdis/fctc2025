# iOS handoff

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
