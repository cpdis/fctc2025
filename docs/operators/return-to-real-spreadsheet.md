# Return to the real attendance spreadsheet

Build 0.1.0 (6) includes shared guests, attendance counts and upcoming birthdays.
Installing it preserves the connection already saved on each phone. It does not
switch a phone from the private test copy to the real spreadsheet.

## Before switching

Complete the server setup below before scanning a real-sheet code. An old endpoint
can load attendance without supporting shared guests or birthdays. Keep each phone
on its test connection until Colin confirms the real server checks have passed.

Configure and verify the authenticated dashboard export before restricting source
workbook access. The setup checks cover both 2025 and 2026.

## Everyone — before changing the connection

1. Open TestFlight, select **FCTC Attendance**, and install **0.1.0 (6)**.
2. Update the existing app. Do not delete or reinstall it.
3. Open FCTC while connected to the internet.
4. Keep the current test connection until Colin confirms the real connection is ready.
5. Check the outbox. Sync any pending test submissions to the test copy.
6. Resolve any saved-change check or conflict before switching. Keep unresolved
   records intact and tell Colin if one remains.
7. Agree on a short pause in app submissions and spreadsheet edits for the switch.

If someone entered a genuine run in the private test copy, tell Colin which date
and run before switching. Compare it with the real sheet before recording it
there. Test names and test runs must not be imported into real attendance.

## Colin — one-time server setup

Colin operates the app deployment. Aaron owns the workbook; Colin and Grant retain
their existing editor access. Aaron and Grant do not need Apps Script or GitHub
access for phone setup. Codex can carry out the technical steps after the edit-free
window is confirmed; Google consent stays with the deploying account, Colin.

1. Confirm all three phones have finished pending test submissions. Confirm that
   nobody will edit the real sheet during setup.
2. Open the real workbook: **250101 FCTC - Run/ Attendance Schedule**. Its ID is
   `1YEKXqp6A4LoGUyg7Rsm3w3MUkbfgRNIAWQkGBYulO2o`.
3. Save a fresh private workbook backup. Keep the script and deployment backups.
   Existing local backups are under `~/.local/share/fctc-release/2026-09-18-build6/`.
4. Open **Extensions → Apps Script**. Confirm script ID
   `16C_TgmKreRubD0ImUbW5vIJyfxf_p7kZ7Wk_SSwaufOtvXNj1-RwuhNR`.
5. Keep the existing `SHARED_SECRET` and `SEASON_SHEET_NAME=2026` properties. Set
   `SHARED_GUESTS_ENABLED=false` and `SHARED_GUESTS_SETUP_ALLOWED=false`.
6. Push the reviewed server files from the `apps-script/` folder with `clasp push`.
   Confirm **Services → Google Sheets API v4** is present. The manifest enables it.
7. Run the read-only `doGet` function once in the editor. Review and accept the
   Google Sheets permission prompt if Google shows one. Its method-refusal response
   is expected; this step does not submit attendance.
8. Update the **existing** web-app deployment. Do not create a replacement URL:

   ```bash
   cd apps-script
   clasp deploy -i AKfycbyzp4iPglc4CRr71UbJRL8ckQaqEc6kWYGeTgTePRhlCPFunMHZioBfv45nj7KhZhw \
     --description 'FCTC build 6: shared guests and birthdays'
   ```

9. Follow [the setup operator procedure](shared-guest-setup.md). Record the actual
   numeric sheet IDs for both **2025** and **2026**. The 2026 ID is `764664511`;
   verify both against the workbook. Prepare one private setup request and run its
   authenticated `read` check. Keep shared writes disabled.
10. In GitHub, configure repository variable `FCTC_ATTENDANCE_ENDPOINT` with that
    existing deployment's `/exec` URL. Configure repository secret
    `FCTC_ATTENDANCE_SECRET` with the same secret used by the real script.
11. Run **Actions → Weekly Data Sync → Run workflow** using branch
    `codex/shared-guest-attendance` and notification mode **preview**. Confirm the
    sync succeeds for both seasons. Review any resulting CSV changes. This run can
    commit refreshed CSV data to the selected branch; it does not send the digest.
12. Merge the reviewed PR after the successful snapshot check. Confirm the dashboard
    deployment succeeds. Future Sunday updates will use authenticated exports.
13. In the real sheet's **Share** dialog, change general access to **Restricted**.
    Retain the existing named owner and editors. Under **File → Share → Publish to
    web**, stop publication if it is enabled. Check anonymous workbook access fails
    and the public dashboard still loads its exported attendance.
14. Set `SHARED_GUESTS_SETUP_ALLOWED=true`, leaving `SHARED_GUESTS_ENABLED=false`.
    Use the operator procedure's `submit` command once with the saved request.
15. Require the separate verified **completed** receipt for the same request,
    workbook and both season IDs. Compare attendance values, formulas, notes and
    run metadata with the backup. Do not replay an uncertain setup request.
16. Set `SHARED_GUESTS_SETUP_ALLOWED=false`. After those checks pass, set
    `SHARED_GUESTS_ENABLED=true`.
17. Verify authenticated state reports shared guests enabled, no pending operation,
    the correct real workbook, both supported seasons, and the recorded birthdays.
18. Generate three private setup codes using the real endpoint and existing secret.
    Label them **Colin iPhone**, **Aaron iPhone**, and **Grant iPhone**. Use the QR
    generator in [the release runbook](../plans/packets/U8-release-runbook.md#10-generate-the-two-setup-codes).
    These codes contain the connection secret. Share each code directly with its
    recipient; do not commit it or put an unprotected copy on a public site.
19. Connect Colin's phone first using the steps below. Confirm it loads the real
    schedule and birthdays. Then tell Aaron and Grant that switching is ready.

## Colin — connect your phone

1. Open FCTC → **Settings → Scan setup code**.
2. Scan the new **Colin iPhone — real spreadsheet** code from another screen.
3. Follow the connection prompt if shown. Leave the app open with internet access.
4. Return Home and refresh. Open **Season** and confirm the real schedule loads.
5. Confirm **Birthdays** below Milestones agrees with the sheet for the next 30 days.
6. Confirm private test guests are absent from the real sheet's guest picker.
7. Give Aaron and Grant their own new codes and confirm they can switch.

## Aaron — connect your phone

1. Install **0.1.0 (6)** in TestFlight and finish the Everyone checklist above.
2. Wait for Colin to confirm the real spreadsheet is ready.
3. Open FCTC → **Settings → Scan setup code**.
4. Scan the new **Aaron iPhone — real spreadsheet** code from another screen.
5. Follow the connection prompt if shown. Return Home and refresh.
6. Open **Season** and confirm the real run dates. Check the Birthdays section.
7. Tell Colin that the real schedule loaded. Do not create a test run in the real sheet.

## Grant — connect your phone

1. Install **0.1.0 (6)** in TestFlight and finish the Everyone checklist above.
2. Wait for Colin to confirm the real spreadsheet is ready.
3. Open FCTC → **Settings → Scan setup code**.
4. Scan the new **Grant iPhone — real spreadsheet** code from another screen.
5. Follow the connection prompt if shown. Return Home and refresh.
6. Open **Season** and confirm the real run dates. Check the Birthdays section.
7. Tell Colin that the real schedule loaded. Do not create a test run in the real sheet.

The iPhone Camera app can also scan a code and open FCTC. In that route, tap
**Connect** when asked. If the code is only on the same phone, display it on another
device, or use Settings' endpoint and shared-secret fields privately, then Save.

## First real run — confirm all three agree

1. Choose one person to record the next genuine run. Avoid simultaneous corrections
   while checking the initial connection.
2. Tick attendees. Compare the live checked count with the headcount. The second
   line includes named and unnamed guests.
3. For a returning guest, select their existing shared name. Use **Name a guest**
   to name an unnamed slot without increasing the total.
4. Confirm and sync the run. Check the same marks, kilometres and guest total in
   the real spreadsheet.
5. Refresh the other two phones and open that run. Confirm all three agree.
6. Review **Settings → Recover guest history** on each phone before promoting a
   guest. Import only genuine old real-sheet runs, matched to the exact person,
   season and run. Exclude private-copy tests. Do not infer saved history from an
   old local “done” record.
7. Finish that guest's recovery on all phones before promotion. Confirm the preview
   retains all runs: eleven guest runs must become eleven member runs.

If a save shows **Checking saved changes**, keep the app and its saved records.
Refresh or use the review/retry action. Do not repeatedly recreate the same change
or reinstall the app. Share the run date and the visible message with Colin.

The app is fully connected when all three phones load the real schedule, share
one confirmed run, and the authenticated dashboard export succeeds. Installing
build 6 alone does not complete the server or connection steps.
