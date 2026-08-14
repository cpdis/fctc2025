# Work-packet conventions (read first, applies to every unit)

You are a solo coding agent building one unit of the FCTC Attendance iOS app.
Master plan: `docs/plans/2026-08-14-001-feat-fctc-attendance-ios-app-plan.md` — read it
before starting; your packet's contract wins on any conflict, the plan wins on anything
your packet doesn't cover.

## Ground rules

- **Integration branch:** `feat/attendance-app`. Work on `feat/attendance-u<N>-<slug>`
  branched from it (or directly in your isolated worktree if the orchestrator says so).
  The orchestrator (Fable) reviews and merges; do not merge or push to `main` yourself.
- **Do not touch** (in every unit): `src/`, `public/`, `index.html`, `vite.config.js`,
  `vercel.json`, `package.json`/`package-lock.json` (except where a packet explicitly
  grants it), `.github/workflows/weekly-data-sync.yml`, the 2025 CSV export in repo
  root, existing docs. The web dashboard must build exactly as before.
- **Zero third-party dependencies** in Swift code (no SPM remotes, no pods). Apps
  Script side: no libraries. Node test tooling uses only `node:test` + built-ins.
- **Environment reality:** you are likely on Linux without Xcode. Swift code must be
  written to compile against iOS 26 SDK / Swift 6 but cannot be compiled here — be
  conservative with API usage, prefer long-stable APIs except where the plan
  explicitly requires iOS 26 features (FoundationModels, Liquid Glass defaults).
  Anything testable without Xcode (Apps Script logic, fixtures, scripts) MUST have
  runnable tests (`node --test`).
- **Node test convention (orchestrator ruling, post-U1):** Node tests are
  `apps-script/test/*.checks.js` registered in `apps-script/test/index.js`, run as
  `node --test apps-script/test` — NOT `*.test.js` (root Vitest globs those and
  breaks `npm test`), and the index aggregator is required (Node 22 `--test`
  doesn't expand a bare directory). `apps-script/package.json` pins
  `"type": "commonjs"` for the dual-environment modules; keep it dependency-free.
- **Sheet safety invariant (all units):** nothing ever writes outside a run row's
  member band + `Actual kms` + `+1's` cells, the member-band header row, or an
  inserted run row. Formula/summary rows and columns are sacrosanct.
- **Naming:** sheet short names (e.g. `Col`, `Alex Kr`) are canonical member keys
  everywhere. Never invent a parallel ID scheme.
- Commit style: repo convention (`feat(...)`, `docs(...)`, `chore(...)`), imperative,
  scoped to the unit.

## Shared API contract (frozen — changes require a plan PR first)

Apps Script Web App, JSON over POST, request `{ secret, action, ...payload }`,
response `{ ok: true, ... } | { ok: false, error, message }`. Actions:

- `getState {}` → `{ roster: [{name, colIndex}], runs: [{rowIndex, date, meet, run,
  approxKm, actualKm, attendees: [name], plusOnes}], seasonYear, sheetRevision }`
- `submitAttendance { rowIndex, expectedDate, expectedRun, attendees: [name],
  plusOnes, actualKm, mode: "merge"|"overwrite", baseRevision }` →
  `{ ok, written } | { ok, conflict: { reason, state } }` — verifies row identity and
  revision before writing; idempotent (absolute values, not deltas).
- `addMember { name }` → `{ roster }` — case/diacritic-insensitive uniqueness,
  alphabetical column insert within the member band.
- `addRun { date, meet, run, approxKm }` → `{ runs }` — date-ordered row insert.

`sheetRevision` = stable hash of header row + run-band cell values.

**Contract addendum (post-U2, authoritative — the deployed API behaves this way):**
- All three write actions ALSO return a fresh `sheetRevision` (additive key), so the
  client can skip a `getState` after a successful write.
- `row_mismatch` / `stale_revision` are never top-level `error`s: they arrive as
  `{ ok: true, conflict: { reason, message, state } }` where `state` is a full
  `getState` payload.
- Additional error codes: `sheet_unreadable`, `busy` (lock contention — retryable),
  `internal_error`, beyond `bad_secret`, `unknown_action`, `duplicate_member`,
  `bad_payload`.
- Cell semantics: a `-` cell is the sheet's "away" marker and is never cleared by
  either mode (only `x` marks are cleared by overwrite); `plusOnes`/`actualKm` sent
  as `null` mean "no opinion" (merge keeps/raises existing, overwrite with a value
  sets absolutely).

## Fixtures

`fixtures/attendance/` (created in U1): season CSV snapshots (2025 + 2026), OCR
line-fixtures (`*.ocr.txt` — the text lines Vision would emit for a WhatsApp
View-votes screenshot), voice transcript fixtures (`*.transcript.txt`), each with an
`*.expected.json` describing the parse result. Add fixtures freely; never edit
another unit's expected files to make your code pass.

## Definition of done (every unit)

1. Your packet's acceptance list passes (run what's runnable; state clearly what
   requires Xcode/macOS and was verified by inspection only).
2. `npm test` (dashboard) still green; `node --test apps-script/test` green if present.
3. A short `HANDOFF.md` note in your unit branch root listing: what you built, how to
   verify on a Mac, and any contract questions for the orchestrator (delete after
   review).
