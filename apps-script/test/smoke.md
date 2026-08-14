# Manual smoke plan — run once against a COPY of the sheet

`node --test apps-script/test` proves the geometry and the router. It cannot prove the
three things that only a real spreadsheet has:

1. **Formulas.** The Node fake stores values; it has no `COUNTA`/`SUM`. Whether the
   derived `Total Attendance per run` column still computes after `submitAttendance`,
   whether the summary ranges *widen* when `addMember` inserts a column, and whether
   the formulas copied into an `addRun` row recalculate — all unknown until a human
   looks.
2. **Real concurrency.** `LockService` is stubbed. Two genuinely simultaneous writers
   are the only way to see it work.
3. **The deployment itself.** Manifest, anonymous access, script properties, the URL.

So: 30 minutes, once, before any phone points at the real sheet.

> **Work on a copy.** Google Sheets > File > Make a copy > "FCTC SMOKE COPY". The
> bound Apps Script project is copied with it, so the copy gets its own script and
> its own deployment. Delete the copy when Phase 1 ships — a stale near-canonical
> twin is a trap.

## 0. Set up (10 min)

- [ ] Make the copy. Note that the copy's tabs are named exactly as the original
      (`2025`, `2026`).
- [ ] Open the copy > Extensions > Apps Script. Project Settings > copy the Script ID.
- [ ] `cd apps-script && cp .clasp.json.example .clasp.json`, paste the **copy's**
      script ID.
- [ ] `clasp push` (uploads `appsscript.json`, `Code.gs`, `SheetOps.js`).
- [ ] Project Settings > Script Properties:
      `SHARED_SECRET = smoke-<something-random>`, `SEASON_SHEET_NAME = 2026`.
- [ ] `clasp deploy --description "smoke"`, note the Web App URL. Open it in a browser
      once and complete the authorization prompt (execute-as-you, anyone-anonymous).

A browser GET should now answer:

```json
{"ok":false,"error":"method_not_allowed","message":"POST JSON to this endpoint. See apps-script/README.md."}
```

Set two shell variables and use them for every step below:

```bash
URL='https://script.google.com/macros/s/…/exec'
SECRET='smoke-…'
post() { curl -sS -L -H 'Content-Type: application/json' -d "$1" "$URL"; echo; }
```

`-L` matters: Apps Script answers a Web App POST with a 302 to a `googleusercontent`
URL. (The iOS client must follow redirects too — `URLSession` does by default.)

**"The derived columns"** below means the two columns immediately right of `+1's`.
The 2025 tab labels them `Total Attendance per run` and `Aggregate Kilometers Per Run`;
on the 2026 tab the header cells are blank but the formulas are there (column AN/AO).
The API never writes them — they must keep computing on their own.

## 1. Auth (2 min)

- [ ] Wrong secret is refused:
      `post '{"secret":"nope","action":"getState"}'`
      → `{"ok":false,"error":"bad_secret",…}`
- [ ] Unknown action is refused:
      `post "{\"secret\":\"$SECRET\",\"action\":\"nonsense\"}"`
      → `{"ok":false,"error":"unknown_action",…}`

## 2. `getState` round-trip (5 min)

```bash
post "{\"secret\":\"$SECRET\",\"action\":\"getState\"}" > /tmp/state.json
```

- [ ] `ok: true`, `seasonYear: 2026`.
- [ ] `roster` has **33** entries, first `Aaron`, last `Wes`, and `Alex 👑` still
      carries its emoji (not `Alex ?` or mojibake).
- [ ] `roster[0].colIndex` is **6** and the last is **38** — open the sheet and confirm
      column 6 is `Aaron` and column 38 is `Wes` (F and AL).
- [ ] `runs` covers the whole season, first run `Fri, 2-Jan` at `rowIndex` **12** —
      confirm that IS row 12 in the sheet.
- [ ] Two runs share `Mon, 26-Jan` with different `run` labels and different
      `rowIndex`es.
- [ ] Note the `sheetRevision` — 16 hex characters.
- [ ] **The dates came back as text** (`"Fri, 2-Jan"`), not as ISO timestamps. If any
      run's `date` looks like `2026-01-02T…`, that cell is date-typed rather than
      text; `SheetOps.dateCellText` should have re-rendered it — flag it.

## 3. `submitAttendance` — the happy path (5 min)

Pick a **future** run (nobody has attended it yet), e.g. the last row of the season.
Record its `rowIndex`, `date`, `run` from `/tmp/state.json`, and screenshot the row
first.

```bash
post "{\"secret\":\"$SECRET\",\"action\":\"submitAttendance\",
  \"rowIndex\":<ROW>,\"expectedDate\":\"<DATE>\",\"expectedRun\":\"<RUN>\",
  \"attendees\":[\"Col\",\"Aaron\"],\"plusOnes\":2,\"actualKm\":7.5,
  \"mode\":\"overwrite\",\"baseRevision\":\"<REVISION>\"}"
```

- [ ] Response is `{"ok":true,"written":N,"sheetRevision":"…"}` and the new revision
      differs from the one you sent.
- [ ] In the sheet: `Col` and `Aaron` now have `x`, nobody else on that row does,
      `+1's` is 2, `Actual kms` is 7.5.
- [ ] **FORMULA CHECK (the important one):** the first derived column on that row
      reads **4** (2 attendees + 2 guests) and the second reads **30** (4 x 7.5).
      If either shows `#REF!`, a stale number, or blank, stop and report it.
- [ ] The rows above and below are untouched; so are the summary rows at the top of
      the tab.
- [ ] Re-`getState`: the run shows `attendees: ["Aaron","Col"]`, `plusOnes: 2`,
      `actualKm: 7.5`.

### Idempotency

- [ ] Send the **exact same request again** (same body, even the now-stale
      `baseRevision` — expect a conflict; resend with the fresh one). Once accepted,
      the sheet is unchanged and `getState` returns the same values. Retrying a queued
      submission must never double-count anything.

### Merge vs overwrite

- [ ] Same row, `mode: "merge"`, `attendees: ["Scott"]`, fresh `baseRevision`.
      → `Aaron`, `Col` **and** `Scott` are ticked. Merge never unticks.
- [ ] Same row, `mode: "overwrite"`, `attendees: ["Scott"]`.
      → only `Scott` is ticked. Overwrite unticks deliberately (Q1, resolved yes).
- [ ] Put a literal `-` in one member's cell on that row by hand, then submit an
      `overwrite` that omits them. The `-` must survive — only `x` is ever cleared.

## 4. Conflict paths (5 min)

**Row identity moved.**

- [ ] Submit with a correct `rowIndex` but a deliberately wrong `expectedRun`.
      → `{"ok":true,"conflict":{"reason":"row_mismatch",…}}`, and **nothing changed in
      the sheet**.

**Someone edited between get and submit** — this is the real one:

- [ ] `getState`, note `sheetRevision`.
- [ ] In the browser, tick any member's box on any run row (a real human edit).
- [ ] Submit against your noted `sheetRevision`.
      → `{"ok":true,"conflict":{"reason":"stale_revision",…}}`, nothing written.
- [ ] `conflict.state` in that response already shows the tick you just made — that is
      what the app's diff screen renders.
- [ ] Re-submit using `conflict.state.sheetRevision` → accepted.

**Revision insensitivity to noise (should NOT conflict):**

- [ ] Edit a cell in the notes block above the header (e.g. the `Notes:` text), then
      submit with your previous revision. It must still be accepted — the revision
      covers the header row and run band only.

## 5. `addMember` (5 min) — the riskiest operation

Screenshot the header row and one summary formula (click the first derived cell on
any run row and copy its formula text) BEFORE this step.

- [ ] `post "{\"secret\":\"$SECRET\",\"action\":\"addMember\",\"name\":\"Zzz Test\"}"`
      → `ok: true`, roster now 34 entries, `Zzz Test` last, `colIndex` 39.
- [ ] In the sheet: a new column sits between `Wes` and `+1's`, header `Zzz Test`,
      all its cells blank.
- [ ] **FORMULA CHECK:** click that same derived cell. Did its range widen
      to include the new column (e.g. `F12:AM12` became `F12:AN12`)? Google normally
      expands a range when a column is inserted **inside** it; inserting at the right
      edge is the ambiguous case, and this insert is at that edge.
      **If the range did NOT widen, that is the finding of this whole exercise** —
      report it; `addMember` will need to insert before the *last* member instead and
      then move the column, or repair the formulas afterwards.
- [ ] Existing attendance did not shift: spot-check three members' columns against
      your screenshot; `getState` shows the same attendees for run row 12 as before.
- [ ] Alphabetical insert in the middle:
      `{"action":"addMember","name":"Bruce"}` → lands between `Anna` and `Cam`, and
      every member to its right shifted one column.
- [ ] Emoji-adjacent ordering: `{"action":"addMember","name":"Alex C"}` → lands between
      `Alex B` and `Alex Kr` (`Alex 👑` sorts as `Alex`).
- [ ] Duplicates rejected: `{"action":"addMember","name":"col"}` →
      `{"ok":false,"error":"duplicate_member",…}` and no column appears.
- [ ] Undo everything: delete the test columns (Edit > Undo works too) and confirm
      `getState` is back to 33 members.

## 6. `addRun` (3 min)

- [ ] `{"action":"addRun","date":"Sat, 24-Jan","meet":"Il Lido","run":"Smoke Parkrun","approxKm":5}`
      → `ok: true`, and in the sheet the new row sits between `Fri, 23-Jan` and the
      first `Mon, 26-Jan` row.
- [ ] The four fixed columns are filled; the member cells are blank.
- [ ] **FORMULA CHECK:** the derived columns on the new row compute (0) rather
      than being empty or `#REF!`. That column is copied from the row above; if it is
      blank, report it.
- [ ] Second run on an existing date:
      `{"action":"addRun","date":"Mon, 26-Jan","meet":"Filament","run":"Smoke 5k"}`
      → lands **below** both existing 26-Jan rows.
- [ ] Duplicate rejected: repeat the previous call → `bad_payload`, "already exists".
- [ ] Delete the smoke rows.

## 7. Concurrency (2 min)

- [ ] Fire two writes at once and confirm both are honoured (or one returns `busy`),
      and that the sheet is not left half-written:

```bash
post '{"secret":"'"$SECRET"'","action":"addMember","name":"Race One"}' &
post '{"secret":"'"$SECRET"'","action":"addMember","name":"Race Two"}' &
wait
```

- [ ] `getState` shows **both** new members, each with their own column, in
      alphabetical order — not one clobbering the other, and not two columns with the
      same name. Delete them afterwards.

## 8. Tear down

- [ ] Delete every test member column and smoke run row from the copy (or just delete
      the whole copy — preferred).
- [ ] Delete the smoke deployment, and remove `apps-script/.clasp.json` if it still
      points at the copy.

## Reporting

Note against each **FORMULA CHECK** what actually happened; those are the only steps
whose answer isn't already known. Anything surprising goes in
`apps-script/HANDOFF.md` under "Needs verification", and any contract change goes
through a plan PR — the API contract is frozen.
