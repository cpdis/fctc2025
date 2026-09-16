# Shared attendance snapshot fidelity

Run this check on a private workbook copy before a production upgrade. Use a
separate local output directory. Never commit copied attendance or test secrets.
The weekly workflow now uses `exportAttendanceSnapshot`, not public CSV downloads.

## Prepare the copy

1. Keep the copy restricted to its owner and authorised testers.
2. Verify the bound script's parent workbook ID before uploading code.
3. Complete shared guest setup for each supported season.
4. Keep other editors out during setup, import, and promotion.
5. Use synthetic guest names and record each test operation UUID.
6. Preserve the original cells, formulas, notes, and metadata as private evidence.

## Verify the eleven-run transfer

1. Select three recorded runs in 2025 and eight in 2026 with available unnamed slots.
2. Record each stable run ID, sheet ID, date, actual distance, headcount, and guest count.
3. Create one synthetic shared guest and import those eleven slots after preview.
4. Confirm both clients show eleven confirmed runs after refresh.
5. Capture the authenticated snapshot before promotion.
6. Preview promotion, including the exact new member name and affected seasons.
7. Commit it once and verify its completed receipt.
8. Refresh both clients and confirm eleven ordinary member runs.
9. Capture the authenticated snapshot after promotion.
10. Validate both snapshots with `validateSnapshot` in `scripts/sync-attendance-snapshot.js`.
11. Serialize each season with `serializeCSV`; compare fields with a CSV parser.
12. Confirm eleven member marks replaced eleven named guest allocations exactly once.
13. Confirm every affected run retains its headcount, actual distance, and aggregate distance.
14. Confirm other member marks, notes, and formula results remain unchanged.
15. Confirm the dashboard parser and milestone loader produce eleven for the member.

The automated integration check runs the production handlers, snapshot client,
CSV parser, dashboard aggregation, and digest loader together:

```bash
npx vitest run scripts/guest-promotion-export.test.js scripts/sync-attendance-snapshot.test.js
node --test apps-script/test
```

The Sheets fake does not evaluate formulas. Copy-sheet screenshots and before/after
cell comparisons remain required evidence for formula recalculation and metadata movement.

## Verify export failures and no-op behavior

1. Check missing and invalid secrets return no snapshot data.
2. Check a pending mutation returns `busy` until its receipt is verified.
3. Check a missing supported season prevents all CSV replacement.
4. Check the snapshot includes every configured year exactly once.
5. Check quoted text, embedded newlines, empty fields, dates, and numbers survive serialization.
6. Repeat the same snapshot. Confirm no CSV or timestamp changes.
7. Pause shared writes. Confirm snapshot reads work and legacy writes remain blocked.
8. Confirm anonymous workbook exports cannot expose auxiliary guest tabs.
9. Confirm the public dashboard remains available from committed CSVs.

A snapshot racing a cooperating promotion must capture all seasons before or all
seasons after the promotion. The same script lock covers both operations. Direct
spreadsheet edits do not use that lock and need the edit-free window.

## Production check after separate approval

Configure repository variable `FCTC_ATTENDANCE_ENDPOINT` and repository secret
`FCTC_ATTENDANCE_SECRET`. Run **Weekly Data Sync** on main with notification mode
**preview**. Check the complete supported-year diff and milestone preview before
any deliberate email send. Failed sync must prevent notification processing.
An unchanged snapshot must create no commit or deployment.

If values differ, keep the copy, request UUIDs, receipts, and CSV diff. Identify
whether the first mismatch appears in the sheet, snapshot, serializer, or parser.
Fix that layer and repeat the check. Do not edit CSVs to hide a mismatch.
