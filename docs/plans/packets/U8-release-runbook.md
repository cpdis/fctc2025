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
5. Run its full test suite. Confirm that all kit tests and the 8 UI tests pass.
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

1. Archive the `FCTCAttendance` scheme in Release mode.
2. Upload the archive with Colin's existing TestFlight process.
3. Do not create a second upload pipeline for this app.
4. Wait for Apple to finish processing the build.
5. Install that same build on Colin's and Aaron's phones.

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

1. Read the JSON printed to the terminal.
2. Confirm the HTTPS endpoint and device name.
3. Open each HTML file locally.
4. Do not upload or commit either file.
5. Remove the files after both phones are configured.

## 11. Configure both phones

Repeat these steps on Colin's and Aaron's phones:

1. Open **Settings** in FCTC Attendance.
2. Tap **Scan setup code**.
3. Allow camera access.
4. Scan that phone's setup code.
5. Confirm that the scanner closes. A valid scan saves the secret to Keychain.
6. Confirm the endpoint and device name in Settings.
7. Tap **Save** only if you edit an imported field.
8. Refresh the roster.
9. Confirm that the current 2026 roster and runs load.
10. Confirm that manual entry remains available when camera access is denied.

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
