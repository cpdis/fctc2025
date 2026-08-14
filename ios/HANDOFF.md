# U3 Handoff

## Built

- Added a typed `SheetAPI` actor for all four frozen actions.
- Added exact request and response DTOs, explicit JSON nulls, conflict payloads,
  write revisions, and all frozen error codes.
- Kept `URLSession` inside `URLSessionTransport`.
- Added SwiftData models for members, scheduled runs, pending submissions, and
  the in-memory attendance draft.
- Added a `SyncEngine` actor with persistent queue states, injected retry timing,
  2/4/8/16-second backoff, restart recovery, parking, events, and cache refresh.
- Reconciled successful writes and conflict state into the local cache.
- Treated a stale-revision retry as success when fresh server state already
  satisfies the absolute submission.
- Rebased later queued submissions after an accepted local attendance write.
- Added service, model, and in-memory SwiftData tests for the U3 acceptance cases.

## Decisions

- Keep a failed optimistic member as `isNew`. A later roster response reconciles
  it by canonical name. This follows U3's local `isNew` reconciliation rule.
- Retry only network and `busy` errors. Keep non-retryable contract errors queued,
  emit `failed`, and wait for a later foreground drain.
- Keep completed pending rows as `done` records instead of deleting them.
- Rebase queued revisions only after a known accepted attendance write. Do not
  rebase after `addMember` or `addRun`, because those actions have no base revision
  and could hide an unrelated sheet edit.

## Verification

- Ran `xcodegen generate` after adding Swift files.
- The required named-device command could not resolve the simulator. The sandbox
  lost its CoreSimulatorService connection and reported no iPhone 17 Pro device.
- Compiled the kit and all test sources successfully with:

  ```bash
  cd ios
  xcodebuild build-for-testing -quiet \
    -project FCTCAttendance.xcodeproj \
    -scheme FCTCAttendanceKit \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .ddata \
    CODE_SIGNING_ALLOWED=NO \
    OTHER_SWIFT_FLAGS='-disable-sandbox'
  ```

- Ran `git diff --check` successfully.
- Did not boot a simulator or run tests, as required by the packet instructions.

The orchestrator should run the named iPhone 17 Pro `build-for-testing` command,
then run the test bundle in an unrestricted CoreSimulator environment.

## Blocker

The workspace sandbox can edit the worktree but cannot write the parent repository
Git metadata. `git add` fails while creating the worktree `index.lock` with
`Operation not permitted`. The implementation is therefore not committed here.
Stage the U3 paths and use this commit when Git metadata is writable:

```text
feat(attendance): add sync data layer

Implement the frozen sheet API contract with typed errors.
Persist and retry attendance writes without losing conflicts.

Co-authored-by: Codex
```

## Contract Questions

None.
