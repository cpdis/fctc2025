# iOS handoff

## U8 — hardening and release

### Built

- Added the Settings setup scanner with an `AVCaptureMetadataOutput` QR reader.
- Added a camera-free parser protocol and HTTPS, secret, and JSON validation.
- Saved valid scanned setup immediately through `AppConfigPersisting`.
- Kept the shared secret behind the existing `SecretStoring` Keychain seam.
- Kept manual entry available for denied, restricted, missing, and simulator cameras.
- Added friendly sync banners, retry actions, conflict routes, and Settings routes.
- Kept busy retry exhaustion distinct from offline and fixed empty-cache failure UI.
- Rechecked camera permission after Settings and routed capture setup failure to manual entry.
- Added first-load, no-run-today, and empty-outbox states.
- Replaced raw screenshot and voice errors with fixed user text.
- Added the 1024 px AppIcon slot, RGB placeholder, and accent-color wiring.
- Added U8 parser, persistence, loading, banner, and bad-secret build tests.
- Added the setup QR CLI, QR encoder, Node checks, runbook, and fidelity guide.

### Decisions

- Used AVFoundation because this screen needs only one QR code type.
- Kept parsing in `FCTCAttendanceKit`; camera code passes only a payload string.
- Made a valid scan save immediately. Manual edits still use the Save button.
- Kept server diagnostics inside services. Views receive stable, friendly text.
- Kept the API contract and sheet write geometry unchanged.
- Generated the placeholder as RGB. It is 1024 by 1024 and has no alpha channel.

### Verification completed here

- Ran `xcodegen generate` successfully.
- Passed the exact `FCTCAttendanceKit` build-for-testing gate.
- Passed the full app code build-for-testing gate for both simulator architectures
  with `EXCLUDED_SOURCE_FILE_NAMES=Assets.xcassets`.
- Reached asset compilation with the exact `FCTCAttendance` gate.
- Could not finish that exact gate because this sandbox has no available simulator
  runtimes. `actool` reports `SimServiceContext supportedRuntimes=[]`.
- Passed `node --test apps-script/test`: 153 checks, 0 failures.
- Ran the QR CLI with a fake secret. It wrote a private mode-0600 HTML file.
- Confirmed the placeholder is a 1024 px RGB PNG with no alpha.
- Passed Node syntax checks, JSON checks, and `git diff --check`.
- Did not boot a simulator or run iOS tests, as the packet requires.
- Could not run root `npm test` because this checkout has no installed `vitest`.
- Applied and rechecked all five retained Compound Engineering review findings.

### Orchestrator actions

1. Replace `Assets.xcassets/AppIcon.appiconset/icon-1024.png` with Colin's photo.
2. Keep the filename, 1024 px size, RGB color, and no-alpha requirement.
3. Regenerate the Xcode project.
4. Run every kit test, including the original 151 tests and the new U8 tests.
5. Run all 7 UI tests and both Node suites.
6. Run the exact app build-for-testing gate where simulator runtimes are available.
7. Review the scanner and all new banners on a physical phone.

### Colin actions

Follow `docs/plans/packets/U8-release-runbook.md` from start to finish. It covers
signing, TestFlight, the real clasp target, the stable deployment ID, setup codes,
both phones, secret rotation, the new season, and the carried device checks.

### Intended commit

Git cannot create the worktree index lock in this sandbox. The orchestrator must
stage these changes and use this commit message:

```text
feat(attendance): harden release setup

Add secure QR onboarding and zero-dependency setup code generation.
Surface sync failures with direct recovery paths and document production release.

Co-authored-by: Codex
```
