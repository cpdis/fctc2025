# U4 Handoff

## Built

- Replaced the static home screen with cached run, outbox, sync, and settings status.
- Added the run picker and the R7 default selection rule, including recorded-run skips.
- Added Review & Confirm with member toggles, detail rows, provenance, quick add, and merge or overwrite review.
- Added the outbox with outstanding-only filtering, retry actions, conflict details, and durable conflict resolution.
- Added settings for the endpoint, Keychain secret, device name, cache refresh, and the U8 QR seam.
- Added MainActor observable view models that consume per-subscriber `SyncEvent` streams.
- Added UI test plans and project target configuration.
- Added unit coverage for all new view models and the new sync paths.

## Decisions

- Keep the SwiftData cache as the UI source of truth. Network work updates the cache through `SyncEngineClient`.
- Broadcast each sync event to every active view-model subscriber.
- Keep resolved submissions as history. Enqueue a new revision for each conflict resolution.
- Store the shared secret only in Keychain. Keep the endpoint and device name in app preferences.
- Roll back an optimistic quick-add member when the direct network request fails.
- Derive a new run's season year from cached scheduled dates. Fall back to the injected clock year when the cache is empty.
- Search retained submission guest names for quick-add suggestions. Exclude roster members and duplicate names.

## Review

- Fixed eight validated behavior findings and two test-hardening findings.
- Covered quick-add rollback, add-run success and failure, full conflict diffs, conflict errors, retry rules, and event fan-out.
- Kept the implementation direct. The simplicity review found no reusable code to adopt.

## Verification

- `cd ios && xcodegen generate`: passed.
- Exact Kit `build-for-testing`: blocked by the outer sandbox. Apple's Observation and SwiftData macro plug-ins returned malformed responses after `sandbox-exec: sandbox_apply: Operation not permitted`.
- Kit `build-for-testing` with `OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'`: passed with `** TEST BUILD SUCCEEDED **`.
- Exact app `build`: blocked by the same compiler plug-in sandbox failure.
- App `build` with the compiler sandbox workaround: reached asset compilation, then stopped because this host has no iOS Simulator runtime.
- Direct app source type check with Swift 6 strict concurrency: passed.
- Direct UI test source type check with Swift 6 strict concurrency: passed.
- `git diff --check`: passed.
- Unit and UI tests were not run. The packet reserves test execution for the orchestrator.
- No simulator was booted. No visual review page was made because the packet forbids simulator use here.

## Contract Questions

None.

## Commit

The work remains uncommitted because `git add` returned:

```text
fatal: Unable to create '/Users/colin/Documents/Personal Projects/FCTC Dashboard/.git/worktrees/u4-ui/index.lock': Operation not permitted
```

Intended commit message:

```text
feat(attendance): build checklist workflow

Add the Reminders-style run, checklist, outbox, and settings flows.
Drive them from the SwiftData cache and durable sync event stream.
Add conflict resolution, secure config storage, and UI test plans.

Co-authored-by: Codex
```
