# FCTC Attendance — Apps Script Web App

The write layer for the iOS attendance app. It is a **container-bound** Apps Script
project living inside the FCTC spreadsheet, deployed as a Web App that speaks JSON
over POST. The iOS app therefore needs no Google OAuth at all — just a URL and a
shared secret.

The original app follows `docs/plans/2026-08-14-001-feat-fctc-attendance-ios-app-plan.md`.
Shared guest work follows the September plan below. New capabilities stay disabled
until copy verification and an explicitly approved production upgrade are complete.
The August smoke result covers the original writer only. Run `test/smoke.md` again
after a write-layer change.

## Shared guest contract (v2)

The [September plan](../docs/plans/2026-09-16-1450-feat-shared-guest-attendance-plan.md)
replaces the original phone-local guest decision. The pure contract is implemented in
`GuestOps.js`, with [shared JSON fixtures and field documentation](../fixtures/attendance/guests/README.md).
The contract does not imply a deployed v2 endpoint. The server must advertise only usable capabilities.

Guests have UUIDs and editable labels. Member keys remain exact canonical sheet names.
Run identity is workbook ID + season sheet ID + row-associated run UUID; row indices are locators.
Attendance is one logical record per guest/run, with explicit present/removed and guest/transferred states.
Named IDs plus the explicit unnamed remainder determine `+1's`. Same-name guests require selection.
Promotion preserves historical attendance and rejects later writes that still treat the person as a guest.

Every v2 mutation has an operation UUID and a verified canonical-request SHA-256 digest.
Receipts distinguish pending, completed, rejected, and reconciled non-application (`not_applied`).
Pending outcomes fence workbook writes until verified; a repeated UUID returns its saved outcome.
The pure module validates contracts. The adapter recomputes digests, enforces revisions,
bounds stored recovery data, and makes related sheet changes atomically.

`setupSharedGuests` requires `SHARED_GUESTS_SETUP_ALLOWED=true`, the exact workbook ID,
and explicit season sheet IDs. It creates hidden tables and run metadata without enabling
writes. `SHARED_GUESTS_ENABLED=true` enables available shared actions after setup.
Setup leaves a durable format marker: setting the enable flag back to false pauses shared
writes but does not permit older apps to overwrite named allocations.
Use the [operator setup procedure](../docs/operators/shared-guest-setup.md) to
prepare and retain the canonical request. After dispatch starts, the helper only
checks status; an absent receipt does not permit another setup attempt.

`getState` accepts an optional `seasonSheetId` for historical navigation. Shared state includes
guest summaries, stable run IDs, named selections, unnamed counts, pending operation IDs,
and `supportedSeasons: [{seasonSheetId, seasonYear}]` for explicit recovery selection.
`getGuestHistory` returns dated entries across configured seasons. Name-only edits use
`renameGuest`; they do not need an attendance or distance change.

Every writer checks the workbook fence while holding the script lock. A pending journal
stores the canonical request, source revisions, planned requests, targets, and receipt location
before dispatch. The final batch includes its completed receipt. `getOperationStatus` verifies
the saved targets before it clears an uncertain operation. A missing receipt after dispatch
is not permission to repeat a batch. A bootstrap interruption before the ledger exists
retains its fence for operator recovery, even if dispatch never started.

The iOS outbox may resend the same saved UUID and digest only when completed
transport metrics prove that its request never started. Missing metrics, a sent
request, or a redirect leave delivery uncertain. Those operations continue receipt
checks after restart. Existing uncertain records cannot infer non-delivery later.

**Narrow sheet-safety extension:** the v2 adapter may maintain `_FCTC_Guests`,
`_FCTC_GuestAttendance`, `_FCTC_Operations`, and run-row developer metadata.
Reviewed promotion may convert original historical run cells inside the normal member band
and decrement their `+1's` cells. Each run's headcount, distance, and formulas must remain unchanged.
Member-column insertion retains the existing right-edge formula protection.
New member summaries copy recognised formulas. Direct earlier-season references are
relocated by member identity when columns move. Unrecognised historical formulas stop
the operation before mutation. This permits no arbitrary changes to unrelated tabs.
Hidden tabs organise data; workbook sharing and publication settings control access.

Focused contract checks: `node --test apps-script/test/guestops.checks.js`.
The legacy contract below remains the compatibility baseline; v2 responses keep its readable fields.

## API contract (frozen — changes require a plan PR first)

Request: `POST` a JSON body `{ secret, action, ...payload }`.
Response: `{ ok: true, ... }` or `{ ok: false, error: "code", message: "..." }`.

| Action | Payload → Response |
|---|---|
| `getState` | `{}` → `{ roster: [{name, colIndex}], runs: [{rowIndex, date, meet, run, approxKm, actualKm, attendees, plusOnes}], seasonYear, sheetRevision, lifetimeTotals: [{name, runs}] }` |
| `submitAttendance` | `{ rowIndex, expectedDate, expectedRun, attendees, plusOnes, actualKm, mode: "merge"\|"overwrite", baseRevision }` → `{ ok, written }` or `{ ok, conflict: { reason, state } }` |
| `addMember` | `{ name }` → `{ roster }` |
| `addRun` | `{ date, meet, run, approxKm }` → `{ runs }` |

`sheetRevision` is a stable hash of the header row + run-band cell values, used for
optimistic concurrency. `submitAttendance` writes **absolute** values (not deltas), so
retrying a queued submission is idempotent — that is what makes the offline outbox safe.

**Sheet-safety invariant:** nothing is ever written outside a run row's member band +
`Actual kms` + `+1's` cells, the member-band header row, or an inserted run row.
Formula and summary rows/columns are sacrosanct. Enforced in code: every write to an
existing run row goes through `writeRowRange_`, which refuses any rectangle
`SheetOps.isWriteWithinBand` rejects, and `test/api.checks.js` re-checks every
recorded write against the band derived from the season fixture.

**Indices on the wire are 1-based sheet coordinates.** `roster[].colIndex` is the
real column, `runs[].rowIndex` the real row — what you see in the Sheets UI, and what
`submitAttendance { rowIndex }` sends straight back.

### Error codes

`bad_secret`, `unknown_action`, `duplicate_member`, `bad_payload` come back as
`{ ok: false, error, message }`. `row_mismatch` and `stale_revision` are **conflict
reasons**, not errors: `submitAttendance` answers
`{ ok: true, conflict: { reason, message, state } }` with a fresh `getState` payload
and writes nothing. Three operational codes round it out: `sheet_unreadable` (the
`SEASON_SHEET_NAME` tab is missing or has no recognisable header row), `busy`
(another writer held the script lock), `internal_error`.

## Files

| File | Role |
|---|---|
| `Code.gs` | Web app entry, authentication, lock helper, and legacy sheet operations. |
| `SheetOps.js` | Pure sheet geometry (header detection, member band, revision hash, insert positions). No I/O, no `require` — see the dual-environment note below. |
| `GuestOps.js` | Pure shared UUID, history, allocation, revision, and operation-request contracts. No Apps Script services. |
| `GuestStore.gs`, `GuestActions.gs` | Shared snapshots, authenticated routes, identity edits, and attendance plans. |
| `GuestSetup.gs`, `SheetBatch.gs` | Explicit setup and precise Sheets v4 request builders. |
| `GuestOperations.gs` | Durable pending journals, atomic receipts, and restart reconciliation. |
| `GuestPromotion.gs`, `GuestPromotionSafety.gs` | Reviewed historical conversion and formula preservation. |
| `GuestImport.gs` | Explicit local-history review and unnamed-slot assignment. |
| `AttendanceExport.gs` | Locked, authenticated snapshot of every supported season. |
| `appsscript.json` | Manifest: V8, web app `ANYONE_ANONYMOUS` / execute as `USER_DEPLOYING`. |
| `.clasp.json.example` | Template for the (gitignored) `.clasp.json`. |
| `.claspignore` | Keeps `test/`, `package.json` and this README out of the pushed project. |
| `test/` | Node tests (`node --test apps-script/test`): sheet geometry, the fake Apps Script runtime, fixture integrity, and setup-QR structure. |
| `test/support/` | Test-only helpers: a quote-aware CSV reader, the season fixture facts, and the in-memory `SpreadsheetApp`/`LockService`/`PropertiesService` fakes. |
| `test/smoke.md` | The manual run-once-against-a-copy plan — the things no fake can prove (formulas, real locking, a real deploy). |
| `make-setup-qr.js` | Zero-dependency CLI that writes a private, self-contained setup QR page. |
| `qr-encode.js` | Shared byte-mode QR encoder used by the CLI and Node checks. |
| `test/verify-sync-fidelity.md` | First-real-run check from the sheet through the weekly CSV sync. |

### The dual-environment module pattern

Apps Script has no module system: every top-level function in a pushed file is a
global that `Code.gs` can call. Node needs `module.exports`. So `SheetOps.js` declares
plain top-level `function`s and exports them at the bottom behind a guard:

```js
function cellText(value) { /* ... */ }

// One namespace object, gathered at the bottom of the file.
var SheetOps = { cellText: cellText /* , ... */ };

if (typeof module !== 'undefined' && module.exports) {
  module.exports = SheetOps;
}
```

That object is a plain global in Apps Script and the CommonJS export in Node, so
`Code.gs` and the tests both say `SheetOps.findHeaderRow(...)`. The tests assert that
`Code.gs` never calls a geometry helper bare, never indexes the grid, and never
re-declares a name SheetOps already exports.

Apps Script skips the block (`module` is undefined there); Node gets a normal CommonJS
module. Consequences to respect:

- **No `require()` / `import` in `SheetOps.js` or `Code.gs`** — the tests assert this.
- **No `SpreadsheetApp` in `SheetOps.js`** — pass arrays-of-arrays in, get plain data
  out. That is what makes the logic testable against the repo's CSV fixtures.

## Running the tests

```bash
node --test apps-script/test        # from the repo root
npm test --prefix apps-script       # same thing
```

Two naming rules keep the two test worlds apart, and both matter:

1. Test files are named `*.checks.js`, **not** `*.test.js`. The repo root runs Vitest
   over the whole tree with its default include; Vitest cannot execute `node:test`
   files, so a `*.test.js` here would break `npm test` for the dashboard.
2. `test/index.js` requires each `*.checks.js`. Node's test runner expands a directory
   argument by matching *its* patterns (which `*.checks.js` does not match), so passing
   the directory resolves to `index.js` — which pulls in every suite. Add a suite by
   dropping a `*.checks.js` file in `test/` and requiring it there.

`apps-script/package.json` exists only to set `"type": "commonjs"` (the repo root is an
ES-module package) and has no dependencies to install.

## Deploy runbook (clasp)

One-time:

```bash
npm install -g @google/clasp
clasp login                       # as the sheet owner (Colin)
cd apps-script
cp .clasp.json.example .clasp.json
# put the bound script's ID in .clasp.json:
#   FCTC spreadsheet > Extensions > Apps Script > Project Settings > Script ID
```

Set the shared secret (never committed):

```
Apps Script editor > Project Settings > Script Properties
  SHARED_SECRET     = <long random string>     # same value goes in the iOS app's Settings
  SEASON_SHEET_NAME = 2026                     # bump each new season
```

Push and deploy:

```bash
clasp push                                  # upload appsscript.json, Code.gs, SheetOps.js
clasp deploy -i <existing-id> --description "FCTC Attendance update"
```

Use **`-i` with the same deployment** every time: the Web App URL stays
stable, so the phones never need reconfiguring. `clasp deployments` lists them; the
first ever deploy (`clasp deploy`) creates the ID to reuse.

Before a production push, re-check `apps-script/.clasp.json`. The smoke run left the
local file pointing at its disposable copy. Set it to the real sheet's bound Script
ID before `clasp push`. See `docs/plans/packets/U8-release-runbook.md` for the full
production sequence.

### Setup QR

Generate one private HTML page per phone:

```bash
FCTC_SETUP_SECRET='<secret>' node apps-script/make-setup-qr.js \
  --url 'https://script.google.com/macros/s/<deployment-id>/exec' \
  --device 'Colin iPhone' \
  --output /tmp/setup-qr-colin.html
```

The command prints the exact payload for review. It is a link, not JSON:

```
fctc-attendance://setup?endpoint=<encoded>&secret=<encoded>&device=<encoded>
```

The scheme is what makes the code work. Generic scanners (the iOS Camera app, Live
Text in Photos) lift a URL out of anything they scan, so an earlier JSON payload sent
people to the endpoint in Safari, which answered `method_not_allowed` and configured
nothing. The app claims this scheme, so the Camera app now offers **Open in "FCTC"**
and the app asks the person to confirm the endpoint host before it connects. The app
still reads the old JSON codes, and Settings still accepts the values by hand.

The HTML needs no network connection. Do not commit or share it. The app stores its
imported secret in Keychain, not UserDefaults.

Authorize once by opening the deployed URL as the deploying user; anonymous access is
what lets the app POST without OAuth, and the shared secret is what stops anyone else.

### Lifetime totals

`lifetimeTotals` sums each member's runs across **every tab whose name is four
digits**, which is how the app shows who is near a milestone. Season tabs are
discovered by name, so a new January needs no script-property change; just name
the tab `2027`. A tab named anything else, `Notes` or `2027 draft`, contributes
nothing. Attendance counts any mark except blank and `-`, matching
`src/utils/dataParser.js`, so the app and the weekly milestone email agree.

### Testing safely

Do U2's manual smoke run against a **copy** of the real spreadsheet (File > Make a
copy), never the canonical sheet. Delete the copy once Phase 1 is done so a stale
near-canonical twin doesn't linger.

### Secret rotation

Change `SHARED_SECRET` in Script Properties, then update the secret in the app's
Settings screen on both phones. No redeploy needed.

### Reviewed guest recovery

`previewGuestImport` accepts a shared `guestId` and explicit `entries`. Each entry
contains the workbook, season sheet ID, stable run ID, displayed date and run label,
and `assignment: "existing_unnamed_slot"`. The response includes the reviewed entries,
allocation changes, `baseGuestRevision` and an opaque `baseRevision`.
`importGuestHistory` submits those fields through the v2 operation protocol. It
names an existing guest slot; it does not change a run's total or distance.
Duplicate guest/run imports return a completed no-op. Missing slots need review.

### Consistent attendance export

`exportAttendanceSnapshot` requires the shared secret and holds the script lock
while reading all supported seasons (currently 2025 and 2026). It returns displayed
cell strings, workbook and sheet IDs, `capturedAt`, and a SHA-256 `snapshotRevision`.
It excludes the auxiliary guest and operation tabs. A pending operation returns
`busy`; a missing season returns `snapshot_invalid`. A pause in guest writes does
not disable this read-only export.

Run `node scripts/sync-attendance-snapshot.js` from the repository root with
`FCTC_ATTENDANCE_ENDPOINT` and `FCTC_ATTENDANCE_SECRET` in the environment. The client
validates the entire snapshot before replacing any supported-year CSV. Unchanged
CSV files leave `last-updated.json` unchanged. Configure the endpoint and secret in
private deployment settings; never put them in a URL or a public artifact.
The client retries transient network errors, HTTP 429/5xx, and `busy` at most four
times. Authentication and invalid snapshots fail without retry. Local replacement
failure restores the previous files; a failed restoration requires local recovery.
