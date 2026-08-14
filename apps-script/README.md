# FCTC Attendance — Apps Script Web App

The write layer for the iOS attendance app. It is a **container-bound** Apps Script
project living inside the FCTC spreadsheet, deployed as a Web App that speaks JSON
over POST. The iOS app therefore needs no Google OAuth at all — just a URL and a
shared secret.

Plan: `docs/plans/2026-08-14-001-feat-fctc-attendance-ios-app-plan.md`.
Status: **scaffold only (U1)** — `doPost` answers
`{ ok: false, error: "not_implemented" }`; U2 implements the four actions.

## API contract (frozen — changes require a plan PR first)

Request: `POST` a JSON body `{ secret, action, ...payload }`.
Response: `{ ok: true, ... }` or `{ ok: false, error: "code", message: "..." }`.

| Action | Payload → Response |
|---|---|
| `getState` | `{}` → `{ roster: [{name, colIndex}], runs: [{rowIndex, date, meet, run, approxKm, actualKm, attendees, plusOnes}], seasonYear, sheetRevision }` |
| `submitAttendance` | `{ rowIndex, expectedDate, expectedRun, attendees, plusOnes, actualKm, mode: "merge"\|"overwrite", baseRevision }` → `{ ok, written }` or `{ ok, conflict: { reason, state } }` |
| `addMember` | `{ name }` → `{ roster }` |
| `addRun` | `{ date, meet, run, approxKm }` → `{ runs }` |

`sheetRevision` is a stable hash of the header row + run-band cell values, used for
optimistic concurrency. `submitAttendance` writes **absolute** values (not deltas), so
retrying a queued submission is idempotent — that is what makes the offline outbox safe.

**Sheet-safety invariant:** nothing is ever written outside a run row's member band +
`Actual kms` + `+1's` cells, the member-band header row, or an inserted run row.
Formula and summary rows/columns are sacrosanct.

## Files

| File | Role |
|---|---|
| `Code.gs` | Web app entry (`doPost` router, auth, LockService). All `SpreadsheetApp` I/O lives here. |
| `SheetOps.js` | Pure sheet geometry (header detection, member band, revision hash, insert positions). No I/O, no `require` — see the dual-environment note below. |
| `appsscript.json` | Manifest: V8, web app `ANYONE_ANONYMOUS` / execute as `USER_DEPLOYING`. |
| `.clasp.json.example` | Template for the (gitignored) `.clasp.json`. |
| `.claspignore` | Keeps `test/`, `package.json` and this README out of the pushed project. |
| `test/` | Node tests for the pure functions (`node --test apps-script/test`). |

### The dual-environment module pattern

Apps Script has no module system: every top-level function in a pushed file is a
global that `Code.gs` can call. Node needs `module.exports`. So `SheetOps.js` declares
plain top-level `function`s and exports them at the bottom behind a guard:

```js
function cellText(value) { /* ... */ }

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { cellText: cellText };
}
```

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
clasp deploy --deploymentId <existing-id> --description "U2 API"
```

Use **`--deploymentId` with the same deployment** every time: the Web App URL stays
stable, so the phones never need reconfiguring. `clasp deployments` lists them; the
first ever deploy (`clasp deploy`) creates the ID to reuse.

Authorize once by opening the deployed URL as the deploying user; anonymous access is
what lets the app POST without OAuth, and the shared secret is what stops anyone else.

### Testing safely

Do U2's manual smoke run against a **copy** of the real spreadsheet (File > Make a
copy), never the canonical sheet. Delete the copy once Phase 1 is done so a stale
near-canonical twin doesn't linger.

### Secret rotation

Change `SHARED_SECRET` in Script Properties, then update the secret in the app's
Settings screen on both phones. No redeploy needed.
