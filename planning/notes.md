# FCTC Dashboard notes

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
- Nothing is pushed. `release/testflight-build-7` holds the shipped code; `ui-refinements` and the three `fix/*` branches are its inputs.
- Before/after review page: `review/ui-refinements/index.html` (gitignored).

### Next Steps
- [ ] Decide how to land the work: merge `release/testflight-build-7` (or its inputs) into `fix-spreadsheet-sync`/`main`, then push when ready.
- [ ] Remove the three agent worktrees under `.claude/worktrees/` (command in the 2026-09-28 worknote; the safety hook blocked it).
- [ ] Fix `ios/Tools/testflight-notes.py`: take an exact build number and a group list; today it picks the latest upload and always attaches FCTC Friends.
- [ ] Open review findings: background-drain cancellation strands unsent rows; another endpoint's guest operation blocks the guest queue; shared `addRun` targets the last-refreshed season; a deferred route blocks later routes; the server writes no receipt for early rejections; per-render SwiftData fetch and JSON decode in `AppRuntime.activeSheetState` and ChecklistView.

### Blockers / Open Questions
- None blocking. Collect Aaron's and Grant's TestFlight feedback on build 8, especially the stricter name matching.
