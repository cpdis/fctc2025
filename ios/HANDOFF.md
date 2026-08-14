# U6 — Screenshot poll import

## Built

- Added Vision OCR behind the `TextRecognizer` protocol. The request uses accurate recognition, English, and no language correction.
- Added stable top-to-bottom observation ordering, multi-image extraction, normalized union, and a four-megapixel OCR limit.
- Added `ScreenshotImportView` with multi-select screenshots, bounded thumbnails, OCR progress, errors, and task cancellation guards.
- Added the modality-neutral `ProposalTriageView`. It renders all frozen proposal tiers and applies only explicit choices.
- Added new-person handling through `commitQuickAdd`, then used the frozen `ChecklistViewModel.applyProposals` seam for OCR provenance.
- Added the nameless-card recovery hint and a two-step SF Symbols coach. The "Don't show again" choice uses `UserDefaults`.
- Added fixture-driven parser tests for all poll OCR fixtures, ordering, union, dedupe, triage tiers, nameless cards, and image downscaling.
- Added UI fixtures and tests for Cancel-before-Apply, collision choice, map-to-existing, add-new, Confirm gating, nameless recovery, and coach persistence.

## Decisions

- Kept `DraftProposalSet`, `DraftProposals.swift`, `DraftProposalTests.swift`, and U5 scanner code unchanged.
- Changed only `ProposalTriageView.onAddPerson` to `async throws`. This lets the shared triage show add failures and block dismissal during Apply.
- Updated `ChecklistViewModel.commitQuickAdd` with the returned sheet revision. A later Confirm now uses the revision created by the member add.
- Decoded photos, resized images, and rendered thumbnails in a detached task. View state keeps only bounded `CGImage` values.
- Kept Vision requests serial. This limits peak memory when several four-megapixel screenshots are selected.
- Limited one import to 12 screenshots. This bounds retained image memory while supporting long polls.

## Verification

- `cd ios && xcodegen generate` — passed.
- `xcodebuild build-for-testing -project FCTCAttendance.xcodeproj -scheme FCTCAttendanceKit -destination 'generic/platform=iOS Simulator' -derivedDataPath .ddata CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'` — passed.
- `xcodebuild build-for-testing -project FCTCAttendance.xcodeproj -scheme FCTCAttendance -destination 'generic/platform=iOS Simulator' -derivedDataPath .ddata CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox' EXCLUDED_SOURCE_FILE_NAMES='Assets.xcassets'` — passed. This compiled the app, kit tests, and UI tests.
- The required app `build` without the exclusion reached `Assets.xcassets`, then failed with `No available simulator runtimes for platform iphonesimulator. SimServiceContext supportedRuntimes=[]`.
- `git diff --check` — passed.
- Did not boot a simulator or run test suites, as required by the packet. The orchestrator must run all kit and XCUITest suites.
- Repository Node test commands could not start in this sandbox. Node exited 139 with `ERROR: SecItemCopyMatching failed -50`.

## Review fixes

- Fixed stale draft revisions after a new member write.
- Made triage await member additions and show errors inside the sheet.
- Disabled triage actions and dismissal during Apply. The view cancels its retained Apply task when it disappears.
- Moved photo decoding and image preparation off MainActor.
- Strengthened UI coverage for all required coach and triage gates.

## Remaining checks

- Run real Vision OCR on representative screenshots during orchestrator review. Unit tests use the required fake recognizer seam.
- Run the UI tests on a simulator. This sandbox has no installed simulator runtime.
- PhotosPicker partial-load failure and in-flight Vision cancellation remain manual checks.

## Contract questions

None. The frozen proposal seam remains intact.

## Commit handoff

Git cannot create the shared worktree `index.lock` in this sandbox. The orchestrator must stage and commit the files.

Intended commit:

```text
feat(attendance): add screenshot poll import

Add on-device poll OCR behind a fakeable recognizer seam.
Add shared proposal triage, coach guidance, and UI fixtures.
Keep draft changes behind explicit Apply and Confirm actions.

Co-authored-by: Codex
```
