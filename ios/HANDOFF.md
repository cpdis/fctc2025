# U7 Handoff

## Built

- Added `SpeechService` behind the `Transcriber` protocol.
- Added sequential speech and microphone authorization.
- Added partial transcript streaming and on-device recognition where supported.
- Added a visible Apple server recognition indicator for fallback sessions.
- Split user Stop from immediate cancellation so the recognizer can return final text.
- Added stale-session guards and full audio teardown for cancel, dismiss, and background paths.
- Added `VoiceEntryViewModel` for permission, recording, finalization, parsing, and triage state.
- Added `VoiceTranscriptAnnotator` using the existing U5 parser and scanner.
- Added the `VoiceEntryView` sheet and the isolated `Dictate…` toolbar block.
- Added a modality-neutral `ProposalTriageView` stand-in with U6's exact initializer.
- Routed confirmed changes through `DraftProposalSet(provenance: .voice)` and `ChecklistViewModel.applyProposals`.
- Added fixture pipeline, permission, final callback, stale callback, server fallback, teardown, and re-record tests.
- Updated the speech permission text to disclose Apple server fallback.

## Decisions

- Keep `stop()` as immediate cancellation for dismissal and background transitions.
- Use `finish()` for the record button. It ends microphone input and waits for final recognition.
- Use a two-second fallback before parsing the latest partial transcript.
- Guard both service callbacks and view-model callbacks with recording identifiers.
- Keep draft precedence only in the frozen proposal seam. Do not duplicate it here.

## U6 Merge Note

Replace `FCTCAttendance/Views/ProposalTriageView.swift` with U6's file at merge.
Keep the `ProposalTriageView(set:onApply:onAddPerson:onCancel:)` call in `VoiceEntryView` unchanged.

## Verification

- `cd ios && xcodegen generate` passed.
- Kit `xcodebuild build-for-testing` passed with `OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'`.
- The exact app `xcodebuild build` compiled Swift but failed in `actool`.
- Exact error: `No available simulator runtimes for platform iphonesimulator. SimServiceContext supportedRuntimes=[]`.
- The app build passed when `Assets.xcassets` was excluded. All app Swift source compiled and linked.
- `node --test apps-script/test` passed: 145 tests.
- `npm test` could not start because this worktree has no `node_modules` directory.
- `git diff --check` passed.
- Per packet instructions, no simulator boot or XCTest run was attempted.

## Orchestrator Checks

- Run all Kit tests and the four XCUITests in an environment with simulator runtimes.
- Test speech and microphone permission prompts on a physical device.
- Test both on-device and Apple server recognition indicators.
- Confirm Stop includes the final spoken words before triage.
- Confirm dismiss and background transitions remove the microphone status indicator.
- Confirm a Settings permission change refreshes the open denied-permission sheet.
- Replace the U7 triage stand-in with U6's shared component, then compile both schemes.

## Contract Questions

None.

## Commit

Git staging is blocked by the shared worktree index permissions:
`fatal: Unable to create '.../.git/worktrees/u7-voice/index.lock': Operation not permitted`

Intended commit message:

```text
feat(attendance): add voice entry

Add live speech capture behind a test seam.
Route parsed voice proposals through shared triage.
Cover fixtures, permissions, teardown, and re-record state.

Co-authored-by: Codex
```
