# U8 release runbook

Use this runbook on Colin's Mac. Do not run production steps from a temporary
worktree. Keep the setup QR and shared secret private.

## 1. Prepare the release checkout

1. Pull the final release branch.
2. Confirm that `git status --short` is empty.
3. Confirm that the selected 1024 px app photo replaced
   `ios/FCTCAttendance/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
4. Run the local checks from the repository root:

   ```bash
   node --test apps-script/test
   npm test
   ```

5. Stop if either command fails.

## 2. Generate and open the Xcode project

1. Generate the project after all file changes:

   ```bash
   cd ios
   xcodegen generate
   open FCTCAttendance.xcodeproj
   ```

2. Select the `FCTCAttendance` target in Xcode.
3. Open **Signing & Capabilities**.
4. Set `DEVELOPMENT_TEAM` to Colin's Apple development team.
5. Confirm that the bundle identifier is `com.cpdis.fctc-attendance`.
6. Select the `FCTCAttendance` and `FCTCAttendanceShare` targets.
7. Confirm that both targets use the App Group
   `group.com.cpdis.fctc-attendance`.
8. Create or enable that App Group for both App IDs in the Apple Developer portal.
9. Refresh the profiles before a device archive or TestFlight upload.

## 3. Run the iOS test gates

1. Select the `FCTCAttendanceKit` scheme.
2. Run its full test suite. Confirm that the original 164 kit tests stay green.
3. Confirm that every new U8 setup, loading, and sync-error test also passes.
4. Select the `FCTCAttendance` scheme.
5. Run its full test suite. Confirm that all kit tests and the 9 UI tests pass.
6. Stop if an original test disappears or any test fails.

The matching command-line build gate is:

```bash
cd ios
xcodebuild build-for-testing \
  -project FCTCAttendance.xcodeproj \
  -scheme FCTCAttendanceKit \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .ddata \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'

xcodebuild build-for-testing \
  -project FCTCAttendance.xcodeproj \
  -scheme FCTCAttendance \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .ddata \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'
```

## 4. Upload the TestFlight build

**Write the "What to Test" notes BEFORE archiving.** Drafting them first forces
you to name what actually changed while the diff is still in front of you, and it
means the notes are ready the moment processing clears rather than being written
in a hurry against a build already in Apple's hands. Draft to a file and pass it
with `--file` in step 3.

Two different fields are easy to confuse:

| Field | Scope | Where |
| --- | --- | --- |
| **What to Test** | per build, what changed | `testflight-notes.py`, step 3 below |
| **Beta app description** | the app overall, rarely changes | App Store Connect, TestFlight tab |

A new feature changes the first. Only a change in what the app *is* touches the
second.

The 2026-08-14 release established the working pipeline. Xcode has no account
session on this Mac, so cloud signing fails; Release signs MANUALLY with the
Apple Distribution certificate and the two App Store profiles (created via the
ASC API, installed locally). The ASC API key `NJDJN4V5L3` (Downloads and
`~/.appstoreconnect/private_keys`) authenticates the upload.

1. Archive:

   ```bash
   cd ios
   xcodebuild archive -project FCTCAttendance.xcodeproj \
     -scheme FCTCAttendance -destination 'generic/platform=iOS' \
     -archivePath .ddata/FCTC.xcarchive
   ```

2. Upload (export-options.plist: method app-store-connect, destination upload,
   manual signing with both profile names, teamID Y62XUYATCS):

   ```bash
   xcodebuild -exportArchive -archivePath .ddata/FCTC.xcarchive \
     -exportOptionsPlist export-options.plist -exportPath .ddata/export \
     -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_NJDJN4V5L3.p8 \
     -authenticationKeyID NJDJN4V5L3 \
     -authenticationKeyIssuerID 69a6de7a-eb61-47e3-e053-5b8c7c11a4d1
   ```

3. Set the "What to Test" notes and attach the build to the tester groups
   (waits for processing on its own):

   ```bash
   python3 ios/Tools/testflight-notes.py "What changed in this build."
   ```

   Write the notes from the user-facing commits since the last upload, as a
   short Dr. Seuss-style rhyme (Colin's standing preference; the beta app
   description sets the tone). The club's full name is the Filament Coffee
   Track Club. Internal testers get the build immediately; external testers
   get it when Apple's (first-build-only) beta review clears.
4. Install that same build on the phones.
5. The distribution certificate expires 2027-08-14; renew via the ASC API
   (certificates endpoint) with a fresh CSR and recreate both profiles.

## 5. Protect the real sheet before deployment

1. Finish `apps-script/test/smoke.md` against a copy of the real spreadsheet.
2. Confirm all formula checks in that guide.
3. Confirm the 2026-08-14 right-edge member fix on the copy.
4. Do not push test code or a smoke secret to the real sheet.
5. Delete the smoke spreadsheet and its deployment after the checks pass.

## 6. Point clasp at the real bound script

`apps-script/.clasp.json` previously pointed at the deleted smoke copy. Never run
`clasp push` until this file points at the real sheet's bound script.

1. Open the real FCTC spreadsheet.
2. Select **Extensions > Apps Script**.
3. Open **Project Settings**.
4. Copy the real bound script's **Script ID**.
5. Set `apps-script/.clasp.json` to this local, gitignored content:

   ```json
   {
     "scriptId": "REAL_BOUND_SCRIPT_ID",
     "rootDir": "."
   }
   ```

6. Compare the ID again before the first push.
7. Never commit `.clasp.json`.

## 7. Set the production script properties

1. Open the real Apps Script project settings.
2. Set `SHARED_SECRET` to a new, long random value.
3. Set `SEASON_SHEET_NAME` to `2026`.
4. Store the secret in Colin's password manager.
5. Never paste the secret into source code, a fixture, a commit, or this runbook.

## 8. Push and create the production deployment once

1. Push the reviewed files:

   ```bash
   cd apps-script
   clasp push
   ```

2. Create the production deployment only if none exists:

   ```bash
   clasp deploy --description "FCTC Attendance production"
   ```

3. Record the returned deployment ID and `/exec` URL in Colin's password manager.
4. Complete Google's authorization prompt as the sheet owner.
5. Confirm that the deployment executes as Colin and allows anonymous web access.
6. Open the `/exec` URL. Confirm that it returns the documented GET refusal.

Plain `clasp deploy` creates a new deployment ID and URL. Run it only for the
first production deployment.

## 9. Update production without changing its URL

Use the recorded deployment ID for every later production update:

```bash
cd apps-script
clasp push
clasp deploy -i <deploymentId> --description "FCTC Attendance update"
```

Do not omit `-i`. A new URL strands both configured phones.

## 10. Generate the two setup codes

Generate one code for each device. Use the same endpoint and secret.

```bash
cd apps-script
FCTC_SETUP_SECRET='<shared secret>' node make-setup-qr.js \
  --url 'https://script.google.com/macros/s/<deployment-id>/exec' \
  --device 'Colin iPhone' \
  --output setup-qr-colin.html

FCTC_SETUP_SECRET='<shared secret>' node make-setup-qr.js \
  --url 'https://script.google.com/macros/s/<deployment-id>/exec' \
  --device 'Aaron iPhone' \
  --output setup-qr-aaron.html
```

For the in-person handoff (scan from a phone screen), generate a badged PNG
per tester instead. The badge shows the tester's initial, the caption their
name, and the script verifies the badged code still decodes via Vision:

```bash
FCTC_SETUP_SECRET='<shared secret>' node apps-script/make-setup-qr-png.js \
  --url 'https://script.google.com/macros/s/<deployment-id>/exec' \
  --device 'Aaron iPhone' --output /tmp/qr-aaron.png
swift ios/Tools/badge-qr.swift /tmp/qr-aaron.png ~/Desktop/setup-qr-aaron.png A Aaron
```

1. Read the `fctc-attendance://setup?…` link printed to the terminal (HTML
   flavour) or trust the VERIFY line (PNG flavour).
2. Confirm the HTTPS endpoint and device name.
3. AirDrop the PNGs to a phone for screen-to-screen scanning.
4. Do not upload or commit any of these files.
5. Remove the files after every phone is configured.

## 11. Configure both phones

The code is a link the app claims, so the **Camera app is the supported path**.
Install the app from TestFlight first, or iOS has nothing to open the link with.

1. Open the iPhone **Camera** and point it at the code.
2. Tap the **Open in "FCTC"** banner.
3. Confirm the endpoint host in the **Connect this phone?** prompt, then tap
   **Connect**. A confirmed link saves the secret to Keychain.
4. Confirm the endpoint and device name in Settings.
5. Refresh the roster.
6. Confirm that the current 2026 roster and runs load.

Two fallbacks stay open, both reached through Settings:

- **Scan setup code** reads the same code from inside the app. Use it when the
  code is on another screen and the Camera banner is inconvenient.
- Manual **Endpoint URL** and **Shared secret** entry, then **Save**. Use it when
  camera access is denied, or when the two people are not together.

## 12. Run the real-device checks

Complete every check on a physical phone before the first real submission:

1. Import representative WhatsApp poll screenshots with Vision OCR.
2. Confirm the recognized names before submission.
3. Test the speech and microphone permission prompts.
4. Confirm the on-device or Apple-server recognition indicator.
5. Speak through the final word, then tap **Stop**.
6. Confirm that the final spoken words appear before triage.
7. Dismiss voice entry. Confirm that the microphone indicator stops.
8. Background voice entry. Confirm that the audio session stops.
9. Deny a permission while its denied-permission sheet is open.
10. Change the permission in Settings. Confirm that the open sheet refreshes.
11. Test a PhotosPicker partial-load failure. Confirm the friendly message.
12. Cancel during OCR. Confirm that the app returns safely without stale results.
13. Disconnect the network and submit a draft. Confirm the parked banner and Retry.
14. Restore the network and tap **Retry**. Confirm that the outbox drains once.
15. Create a stale sheet revision. Confirm the conflict badge and resolution sheet.
16. Set a wrong secret briefly. Confirm that the app routes to Settings with clear text.
17. Restore the production secret before the real submission.
18. Confirm the no-runs-today and empty-outbox states.
19. Enable run reminders. Test allow and deny permission paths.
20. Tap a delivered reminder. Confirm that its checklist opens.
21. Share 1 and 12 screenshots from Photos. Confirm that the import offer appears.
22. Dismiss one shared import. Confirm that the offer does not return.
23. Run both Attendance shortcuts. Confirm the checklist and dictation routes.
24. Queue an offline submission. Background the app and verify one background drain.

## 13. Record the first real run

1. Record one real run on one phone.
2. Confirm its marks, plus-ones, and actual kilometres in the real sheet.
3. Refresh the other phone.
4. Confirm that it shows the same sheet state.
5. Complete `apps-script/test/verify-sync-fidelity.md`.
6. Confirm that the dashboard renders the synced row.

## 14. Rotate the shared secret

1. Generate a new long random secret.
2. Prepare two new local setup codes with the existing production URL.
3. Change `SHARED_SECRET` in the production script properties.
4. Scan the new code on Colin's phone. The scan saves it to Keychain.
5. Refresh and confirm that the phone connects.
6. Repeat the scan and refresh on Aaron's phone.
7. Remove the local QR files.
8. Remove the old secret from the password manager.

The phones will show the Settings prompt between steps 3 and 6. A secret change
does not need `clasp push` or a new deployment.

## 15. Start a new season

1. Create the new season tab in the real spreadsheet.
2. Confirm its header, formulas, and run rows before app use.
3. Set `SEASON_SHEET_NAME` to the exact new tab name.
4. Open each phone and refresh once.
5. Confirm that `getState` returns the new year, roster, and runs.
6. Let the app replace its old cache. No app update or new QR is required.
7. Update the dashboard weekly-sync `CURRENT_YEAR` and `SHEET_GID` separately.
8. Register the new dashboard year as described in the root README.

Do not create a new Apps Script deployment for a new season. The stable endpoint
reads `SEASON_SHEET_NAME` on each request.
