# R11 weekly-sync fidelity check

Run this check after the first real attendance submission. It proves that the
weekly dashboard export preserves the same cell values as a manual sheet edit.

## Prepare two comparable rows

1. Choose the first real run written by the app.
2. Record its Date, Run, row number, attendance marks, plus-ones, and actual kilometres.
3. Choose an unused scheduled run in the real season tab as the control row.
4. Enter the control values by hand in Google Sheets.
5. Use lowercase `x` for each attendance mark.
6. Leave every absent member cell blank.
7. Do not enter `0` in a blank member or plus-one cell.
8. Record both row numbers and take one screenshot before the sync.
9. Record the control row's original values so you can restore them after approval.

## Run the weekly workflow now

1. Open the repository on GitHub.
2. Select **Actions > Weekly Data Sync**.
3. Select **Run workflow** for the release branch.
4. Wait for the workflow to finish successfully.
5. Open its commit or artifact diff for `public/data/2026.csv`.
6. Pull the workflow commit before a local comparison.

## Compare cell values

Compare the app row and control row by CSV field. Ignore sheet formatting, formulas,
comments, and visual style. Check these values exactly:

1. Confirm Date, Meet, Run, Approx. kms, and Actual kms.
2. Confirm every member column in header order.
3. Confirm that each attendance mark is lowercase `x`.
4. Confirm that every absence is an empty CSV field.
5. Confirm that no empty field became `0`, `0.0`, `false`, or a space.
6. Confirm the `+1's` value and its blank behavior.
7. Confirm that the app row and manual row are indistinguishable when their
   intended inputs are the same.
8. Confirm that derived sheet formulas still show the expected totals.
9. Open the dashboard and confirm that the run renders with the same attendance.
10. Restore the control row to its exact original values after the check passes.
11. Run one more `getState` refresh and confirm that the restore caused no formula damage.

For a strict local field comparison, copy the two CSV lines into temporary files.
Then use `diff -u control-row.csv app-row.csv`. Do not edit the synced CSV to make
the comparison pass.

## If any value differs

1. Stop the release check.
2. Keep the sheet rows, workflow run, CSV diff, and screenshots as evidence.
3. Do not normalize casing or replace blanks in the CSV by hand.
4. Identify whether the difference first appears in the sheet or during CSV export.
5. If the sheet differs, inspect the app request and Apps Script write range.
6. If only the CSV differs, inspect the published export and weekly fetch validation.
7. Confirm that the sheet-safety invariant still holds before any retry.
8. Fix the source of the difference and add a regression test.
9. Repeat the real submission and this full check.
10. Do not approve the release until the two rows match by cell value.
