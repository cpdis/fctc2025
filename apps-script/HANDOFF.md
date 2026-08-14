# U2 handoff — Apps Script Web App

Delete this file after review.

## What landed

| File | What it is |
|---|---|
| `SheetOps.js` | Pure sheet geometry. Header detection, member band, run lookup, revision hash, alphabetical/date insert positions, `buildRowWrite`, and the band-bounds guard. No `SpreadsheetApp`, no `require`. |
| `Code.gs` | The impure shell: `doPost` router, secret check, `LockService`, the four actions, structured errors, conflict responses. Every geometry decision is a `SheetOps.*` call. |
| `test/sheetops.checks.js` | U1's scaffold checks + the geometry suite, table-driven over both season CSVs. |
| `test/api.checks.js` | `Code.gs` running for real inside a fake Apps Script runtime, against fixture grids. Contract shapes, conflicts, writes, locking. |
| `test/support/` | Quote-aware CSV reader, season fixture facts, `SpreadsheetApp`/`LockService`/`PropertiesService`/`ContentService` fakes. |
| `test/smoke.md` | The manual plan for a real sheet copy (below). |

`node --test apps-script/test` → **145 tests, 145 pass**.
`npm test` (dashboard Vitest) → unchanged and green. No files outside `apps-script/`
were touched; no fixtures were added or edited.

## Needs verification against a real sheet copy

`test/smoke.md` is the script. Three of its steps are genuinely unknown — everything
else is confirmation. In rough order of risk:

1. **Does `addMember`'s column insert widen the sheet's own formulas?** (smoke §5)
   The new column is inserted *before* the `+1's` column, i.e. at the right-hand edge
   of the member band. Google Sheets reliably expands a range when a column is
   inserted strictly inside it; at the boundary it is ambiguous, and this is the
   boundary. If `Total Attendance per run` does **not** widen to include the new
   member, `addMember` needs a different strategy (insert before the *last* member,
   then move the column — or rewrite the formula afterwards). **This is the one thing
   I would not ship without checking.**
2. **Do the formulas copied into an `addRun` row recalculate?** (smoke §6)
   An inserted row starts formula-less, so `copyDerivedColumns_` copies the columns
   right of `+1's` from the neighbouring run row via `Range.copyTo` (relative refs
   should re-point at the new row). The fake has no formula engine, so it only
   asserts that exactly one copy happens and that it starts right of `+1's`.
3. **Are the sheet's Date cells really text?** (smoke §2)
   Everything here assumes `"Fri, 2-Jan"` strings, as the CSV exports show.
   `SheetOps.dateCellText` also renders a genuine `Date` cell back into that form, so
   a re-typed cell degrades gracefully — but nobody has seen `getValues()` on the real
   tab.

Lower-risk, still worth an eyeball: `LockService` under two simultaneous writers
(smoke §7), and that a Web App POST's 302 redirect is followed (curl needs `-L`;
`URLSession` does it by default — U3 should not disable it).

## Contract questions for the orchestrator

1. **Additive keys on write responses.** The contract says `submitAttendance` →
   `{ ok, written }`. I also return `sheetRevision`, and `addMember`/`addRun` return
   it alongside `roster`/`runs`. It saves the app an immediate `getState` after every
   write and keeps the outbox draining without a refetch. Purely additive — U3's
   decoder ignores unknown keys — but say the word and I will drop it.
   Same question for `conflict.message` (the contract names `{ reason, state }`;
   I add a human-readable `message` for the diff screen and for debugging).
2. **Three error codes beyond the packet's list.** `sheet_unreadable` (the
   `SEASON_SHEET_NAME` tab is missing / has no recognisable header row), `busy`
   (another writer held the script lock past the 20s timeout), `internal_error`
   (anything unforeseen, so the app never gets an HTML stack trace). The packet's six
   codes cover request-level failures only and had nothing to say about these; they
   are reported through the same `{ ok:false, error, message }` envelope.
3. **`row_mismatch` / `stale_revision` are conflict *reasons*, not error codes.**
   The packet lists them among the structured errors, but also says
   `submitAttendance` returns a `conflict` instead of writing when row identity or
   revision don't match — so they are delivered as
   `{ ok:true, conflict:{ reason: "stale_revision", … } }` and never as
   `{ ok:false, error }`. That is the reading the Swift stub in U1
   (`SubmissionOutcome.conflict(reason:state:)`) already assumes.
4. **Indices are 1-based sheet coordinates.** `roster[].colIndex` and
   `runs[].rowIndex` are the row/column numbers a human sees in Sheets, so
   `submitAttendance { rowIndex }` needs no translation on either side. The packet
   didn't specify a base; U3 should assume this one.

## Deliberate decisions worth knowing about

- **`buildRowWrite` takes a 5th `options` argument** (`{ mode, existingValues,
  existingPlusOnes, existingActualKm }`) beyond the packet's four positional
  parameters. Merge semantics are meaningless without the existing row, and passing it
  explicitly keeps the function pure.
- **A `-` in a member cell is never destroyed**, in either mode. The sheet uses `-`
  for "away / not recorded"; only an `x` is ever cleared. Overwrite still unticks
  attendees (Q1: resolved yes) — it just does not eat Colin's annotations.
- **`plusOnes` / `actualKm` of `null` mean "no opinion", not zero.** The phone
  frequently has no distance; the sheet often does. `merge` raises `+1's` to the max
  of submitted and existing (union-flavoured); `overwrite` sets it absolutely.
- **`getState` does not take the lock**; the three write actions do. A read that
  blocks behind a write buys nothing at club scale.
- **Revision covers the header row + every run row from `Date` to `+1's`.** The notes
  band above the header and the derived columns to the right are excluded — they
  change on their own and would produce phantom conflicts. Tested both ways.
- **Run identity is date + run label, both normalized** (26-Jan matches "Mon, 26-Jan";
  "Half - Invasion Day" matches "Half- Invasion Day"). The two seasons punctuate the
  Invasion Day runs differently, and both have two runs on that date.
- **The fake Apps Script runtime in `test/support/`** is a behavioural stand-in, not
  an emulator: it has no formula engine, and `copyTo` copies values while recording
  the intent. Anything about recalculation belongs to `smoke.md` by construction.

## Open, not blocking

- `addRun` inserts the row and copies the derived columns, but does **not** copy
  conditional formatting or data validation (pub-hol shading etc.). If Colin's rows
  carry formatting worth preserving, `insertRowBefore` inherits from the row above in
  Sheets — worth a look during the smoke run.
- A season tab with a blank header cell *inside* the member band is treated as a
  spacer and skipped (the roster stays honest, and nobody's column index moves). No
  such tab exists today; if one ever does, that is the behaviour.
