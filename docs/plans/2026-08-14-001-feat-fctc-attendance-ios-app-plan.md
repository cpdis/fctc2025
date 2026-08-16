---
title: "feat: FCTC Attendance — iOS app for multi-modal run attendance capture, synced to the canonical Google Sheet"
type: feat
status: active
date: 2026-08-14
---

# feat: FCTC Attendance — iOS app for multi-modal run attendance capture, synced to the canonical Google Sheet

## Summary

Build a native iOS app (SwiftUI) that lets Colin or Aaron record attendance and actual
distance for each FCTC run, immediately after the run, using any of three input
modalities: (1) a manual roster checklist, (2) OCR of WhatsApp poll screenshot(s) that
pre-populates the checklist, and (3) voice entry that pre-populates the checklist. All
three modalities converge on a single **Review & Confirm** screen; a confirmed submission
writes straight back to the **Google Sheet, which remains the canonical record**. The UI
takes Apple's Reminders app as its design reference: grouped inset lists, circular
check toggles, tinted section icons, a quick-add row. The
existing dashboard pipeline (weekly CSV export → this repo → Vercel) is untouched — the
app is a new *writer* to the sheet, not a replacement for it. Sheet writes go through a
small Google Apps Script Web App API (versioned in this repo) so the iOS app never needs
Google OAuth, and structural edits (new member column, ad-hoc run row) are done where
they're easy and safe. The plan closes with an agent-orchestration section: the work is
cut into self-contained implementation units with explicit contracts so Fable can
orchestrate Opus and Codex agents to build them in parallel.

---

## Problem Frame

Attendance today is recorded by hand in the Google Sheet: after each run someone opens
the sheet on a phone, scrolls a 40-column grid to today's row, and taps `x` into the
right member cells — error-prone on mobile (wrong row, wrong column, missed members) and
annoying enough that it gets deferred or forgotten. The information needed usually
already exists in two other forms: the WhatsApp poll taken earlier in the week ("who's
coming Friday?") and the memory of whoever led the run ("Kim, Grant and Adam came").

The sheet cannot be replaced: it feeds the dashboard sync, holds the club's formulas and
history, and is the format everyone trusts. So the app's job is narrow and precise —
capture *who attended* and *actual kms* with minimum friction, then write it into the
correct cells of the canonical sheet.

Facts about the sheet that shape the design (verified against `public/data/2026.csv` and
the 2025 export):

- One tab per season. The **entire season is pre-scheduled**: 162 run rows for 2026
  already exist with `Date`, `Meet`, `Run`, `Approx kms` filled and attendance blank.
  The app therefore *selects* an existing row and fills it; creating a row is an edge
  case (e.g. the second "Invasion Day" run on 26-Jan).
- Grid schema: header row (found by content, not position — it drifts between seasons)
  is `Date, Meet, Run, Approx kms, Actual kms, <one column per member>, +1's, …`. The
  member band is "every column between `Actual kms` and `+1's`" — the same rule
  `src/utils/dataParser.js` already uses. Attendance is a literal `x`; members are in
  alphabetical order; new members joined mid-season in 2026 (Alex B, Dan B, Deano), so
  **column insertion mid-season is a real, recurring operation**.
- Two runs can share a date, so a run row is identified by `Date + Run` (and row index
  once resolved), never by date alone.
- Summary/formula rows sit above the header and formula columns sit after `+1's`; the
  app must never write into them.

## Requirements

- R1. The Google Sheet remains the canonical record. Every confirmed submission in the
  app lands in the sheet; any other storage (on-device cache, queue) is subordinate and
  reconstructible from the sheet.
- R2. **Checklist modality**: for a selected run, show the full member roster as a
  checklist (roster read live from the sheet's header, never hardcoded), plus a `+1's`
  guest count and an `Actual kms` field.
- R3. **New member**: an "Add person" affordance creates a new member column in the
  sheet (alphabetical position within the member band) and adds them to the roster.
- R4. **Screenshot modality**: import one or more screenshots of a WhatsApp poll; OCR
  them on-device; extract voted names; fuzzy-match against the roster; pre-check the
  matched members on the Review screen. Unmatched names surface as suggestions (map to
  an existing member or add as new). The user can then check/uncheck freely before
  confirming — poll "yes" ≠ attended.
- R5. **Voice modality**: dictate attendance ("Kim, Grant and Adam came, plus two
  guests, we did 8.7k"); transcribe on-device; extract names/guest-count/distance;
  pre-fill the Review screen the same way.
- R6. All modalities converge on one **Review & Confirm** screen showing exactly what
  will be written (run, date, checked members, +1's, actual kms) before anything
  touches the sheet.
- R7. Run selection defaults to the most recent scheduled run at or before *now*
  (usually "today's run"), with a picker for any other row and a create-row fallback
  for unscheduled runs.
- R8. Sync is safe: read-modify-write against the live sheet, explicit warning if the
  target row already has attendance marks (offer merge or overwrite), and no writes
  outside the run row / member band / `Actual kms` / `+1's` cells.
- R9. Offline-tolerant: a confirmed submission that can't reach the network is queued
  on-device and retried; the queue is visible in the app.
- R10. Both Colin's and Aaron's phones can use the app (TestFlight distribution); the
  write endpoint is protected by a shared secret so only the app can write.
- R11. The dashboard repo's existing sync and parser continue to work unchanged; the
  app's writes must produce cells indistinguishable from hand-entered ones.
- R12. The plan defines implementation units with contracts precise enough for
  independent coding agents (Opus / Codex, orchestrated by Fable) to build in parallel.

## Scope Boundaries

- **No replacement database of record.** SwiftData on-device is a cache + outbox only.
  If a "real" secondary store is ever wanted, it bolts onto the Apps Script layer later
  without touching the app.
- **No Android / web app** this round. iOS native only (two known users, both iPhone).
- **No live WhatsApp integration.** WhatsApp has no consumer API for reading polls;
  screenshots + OCR is the deliberate, ToS-safe design.
- **No editing of historical seasons** (2025 tab is frozen). The app targets the
  current-season tab only, configured server-side in the Apps Script.
- **No custom design system.** The app adopts stock iOS 26 SwiftUI components and the
  system Liquid Glass chrome, styled after Reminders (see Design Language below); no
  bespoke theming beyond an accent color and app icon.
- **No auth beyond the shared secret** — no accounts, no Google Sign-In in the app, no
  per-user identity (submissions may carry a device name for the audit trail).
- **No changes to the sheet's own formulas/summary structure**; the Apps Script writes
  only the cells listed in R8 and inserts member columns/run rows using operations that
  preserve formulas.
- **Dashboard changes: none.** (The weekly sync will simply pick up better data.)

### Deferred to Follow-Up Work

- Strava enrichment: auto-fill `Actual kms` from the run leader's Strava activity.
- Post-run push notification ("Record attendance for Friday Soft Sand?") at
  scheduled-run time + duration.
- Cloud LLM parsing (Claude API) as a further fallback if on-device Foundation Models
  parsing (now in scope, see below) proves insufficient on real inputs.
- In-app season stats (the dashboard already does this well; a WebView link suffices).
- App Store release (TestFlight is enough for two users indefinitely, 90-day builds).

---

## Context & Research

### Why an Apps Script Web App as the write layer (the pivotal decision)

Three candidate write paths were considered:

1. **Google Sheets REST API directly from the app, per-user Google OAuth.** Requires a
   GCP OAuth client + consent screen; `spreadsheets` is a *sensitive* scope, so an
   unverified app in Testing mode expires refresh tokens every 7 days (weekly re-login
   for Aaron — unacceptable), and Production mode shows scary unverified warnings or
   demands a verification review. Also puts the fiddly structural logic (find header
   row, insert column without breaking formulas) in Swift against a raw values API.
2. **Custom backend (e.g. Vercel serverless in this repo) + Google service account.**
   Works, but adds a GCP project, key management in Vercel env, and a Node reimplementation
   of sheet-structure logic; the service account must be granted editor on the sheet.
3. **Google Apps Script Web App bound to the spreadsheet** (deployed "execute as
   Colin", "anyone with the link", shared-secret checked in the request body).
   *Recommended.* Zero OAuth in the app; `SpreadsheetApp` makes the structural
   operations (insert column alphabetically, formulas auto-adjust; `LockService` for
   write serialization) trivial and battle-tested; deploys are versioned; quotas
   (20k URL-fetch-free executions/day) are ~1000× beyond club needs; the script source
   lives in this repo under `apps-script/` and is pushed with `clasp`, so it's
   reviewed and versioned like everything else.

Trade-off accepted: the shared secret ships in the app binary. Threat model is "random
internet", not "motivated attacker who has Aaron's phone"; the secret is rotatable in
one place (script property + app config), and the endpoint validates every request
shape. This is proportionate for a two-user club tool.

### API contract (Apps Script Web App, JSON over POST)

All requests: `{ "secret": "...", "action": "...", ...payload }`. All responses:
`{ "ok": true, ... }` or `{ "ok": false, "error": "code", "message": "..." }`.
Actions (`doPost` router):

| Action | Payload → Response | Notes |
|---|---|---|
| `getState` | `{}` → `{ roster: [{name, colIndex}], runs: [{rowIndex, date, meet, run, approxKm, actualKm, attendees:[name], plusOnes}], seasonYear, sheetRevision }` | One round-trip bootstrap; `sheetRevision` is a hash of the header+run band used for optimistic concurrency. |
| `submitAttendance` | `{ rowIndex, expectedDate, expectedRun, attendees:[name], plusOnes, actualKm, mode: "merge"\|"overwrite", baseRevision }` → `{ ok, written, conflict? }` | Verifies row identity (`expectedDate`/`expectedRun` match the live row) *and* revision before writing; returns `conflict` with fresh state instead of writing blind. Writes `x`/blank across the member band, `Actual kms`, `+1's`. `LockService` wraps the read-check-write. |
| `addMember` | `{ name }` → `{ roster }` | Validates uniqueness (case/diacritic-insensitive), inserts column at alphabetical position within the member band, writes header cell, returns updated roster. |
| `addRun` | `{ date, meet, run, approxKm }` → `{ runs }` | Inserts a row in date order below the header band; edge-case path only. |

Idempotency: `submitAttendance` is naturally idempotent (absolute cell values, not
deltas), which is what makes the offline retry queue safe.

### Design language: Apple Reminders as the reference (decided by Colin)

The attendance problem is structurally the Reminders problem — a titled list of
checkable rows — so the app borrows its idioms wholesale rather than inventing UI:

- **Home = "list of lists"**: large-title screen with tinted circular-icon rows
  (Today's Run, Upcoming, Past Runs, Outbox), Reminders-style summary tiles at top
  (runs this week, unsynced count).
- **Checklist screen = a Reminders list**: grouped inset list, one row per member,
  a **circular check toggle on the left** that fills with the accent color when
  attending (Reminders' completion circle, not a square checkbox); provenance
  (OCR/voice-proposed vs. confirmed) shown as a subtle trailing badge; swipe actions
  for quick uncheck/flag; pull-down search to jump to a name.
- **Quick-add row** pinned at the list bottom — "Add person…" behaves like
  Reminders' "New Reminder" inline row (type name, return commits via `addMember`).
- **Detail affordances**: `Actual kms` and `+1's` presented like Reminders'
  date/priority detail rows above the member list; the Confirm action is a prominent
  toolbar button, disabled until the draft differs from the sheet.
- **System everything**: iOS 26 Liquid Glass toolbars/tab chrome, SF Symbols, semantic
  colors, Dynamic Type, standard sheet presentation for screenshot/voice import flows.
  No custom components unless a stock one genuinely can't express the interaction.

### On-device intelligence (no server round-trips for OCR/voice)

- **Structured parsing via Foundation Models (iOS 26)**: with the minimum raised to
  iOS 26, Apple's on-device LLM (`FoundationModels` framework) is available on
  Apple-Intelligence-capable devices. Guided generation (`@Generable` structs) turns a
  messy voice transcript or OCR'd poll text directly into a typed
  `{ names: [String], plusOnes: Int?, distanceKm: Double? }` — free, offline, private.
  This is the **primary parser** for both smart modalities, wrapped behind the same
  `NameExtractor` protocol with the deterministic heuristics below as fallback
  (model unavailable — device without Apple Intelligence, model still downloading —
  or low-confidence output). Extracted names still go through `NameMatcher`; the
  model proposes, the roster disposes.
- **OCR**: Vision framework (`VNRecognizeTextRequest`, `.accurate`, language `en`).
  WhatsApp poll screenshots are high-contrast UI text — near-perfect recognition. The
  interesting work is *parsing*: poll screenshots contain the question, options
  ("Yes"/"No"/day names), vote counts, and — after tapping "View votes" — voter names
  grouped under options. Strategy: instruct the user (one-time coach screen) to
  screenshot the **"View votes" detail view**, which lists plain names; parser drops
  known chrome lines (option labels, counts, timestamps) and treats remaining lines as
  candidate names. Multi-screenshot stitching = union of candidates with dedupe.
- **Voice**: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` where
  available. Parsing = tokenize transcript, strip stop-phrases ("came", "said they",
  "plus", "and"), extract number+`k`/`km` as distance, number+"guests/plus-ones" as
  +1's, remaining tokens → name matcher.
- **Name matching** (shared by both): normalized Levenshtein/Jaro-Winkler against the
  roster with nickname table (`Col`→Colin is *already* how the sheet names people —
  the sheet's short names are the canonical keys; the nickname table maps common
  long-forms and OCR/ASR variants *to* sheet names, e.g. "Colin"→`Col`,
  "Alex Kravchenko"→`Alex Kr`). Confidence tiers: auto-check (≥0.85), suggest
  (0.6–0.85, shown as "Did you mean…"), unmatched (offer add-as-new). The 2026 roster
  has near-collisions (`Alex 👑` / `Alex B` / `Alex Kr`, `Dan` / `Dan B`,
  `Laura E` / `Laura K`) — ambiguous first-name-only hits must *suggest all
  candidates*, never auto-pick.

### Existing repo assets to reuse

- `src/utils/dataParser.js` — the header-detection and member-band rules to port to
  Apps Script (same tolerance, same band definition).
- `.github/workflows/weekly-data-sync.yml` — already holds `SHEET_ID`; the Apps Script
  is bound to that same spreadsheet. Nothing changes here.
- `public/data/2026.csv` + `src/test/fixtures/` — realistic fixtures for parser tests
  on the Apps Script side (run via `clasp`-pushed test function or a Node port of the
  pure functions — see U2).

---

## Key Technical Decisions

1. **Sheet-write layer = Apps Script Web App** (rationale above). Source versioned in
   this repo at `apps-script/`, deployed with `clasp`; secret in Script Properties.
2. **iOS: SwiftUI, minimum iOS 26 (decided by Colin), Xcode 26 / Swift 6, SwiftData,
   zero third-party dependencies.** Vision, Speech, PhotosUI, FoundationModels, and
   URLSession cover everything; no CocoaPods/SPM supply chain. Raising the floor to
   iOS 26 buys Liquid Glass for free and, more importantly, on-device Foundation
   Models for structured parsing (see above) — acceptable because the entire user
   base is two known, current iPhones.
3. **Monorepo**: the app lives at `ios/FCTCAttendance/` in this repo, beside
   `apps-script/`. The sheet schema knowledge, fixtures, and both writers (weekly sync
   reads, app writes) stay in one reviewable place. The Vite build is untouched
   (`vercel.json`/CI don't glob those directories).
4. **All modalities are pre-fill strategies over one draft model.** `AttendanceDraft`
   (run, checked-set, +1's, actualKm, provenance per check: manual/ocr/voice) is the
   single source the Review screen renders; OCR and voice only ever *propose* checks.
5. **Optimistic concurrency + explicit merge/overwrite** instead of locking UX: with
   two writers at club scale, conflicts are rare; when detected (revision or row
   mismatch), the app re-fetches and shows a diff, never silently clobbers (R8).
6. **On-device OCR/ASR, heuristic parsing first.** Deterministic, offline, free, and
   testable with fixture transcripts/screenshots; LLM fallback is a deferred bolt-on
   behind the same `NameExtractor` protocol.
7. **Roster is always the live sheet header** — fetched at launch/refresh, cached in
   SwiftData for offline, never compiled in. This is exactly the schema-tolerance
   lesson the 2026 dashboard redesign learned (fixed member lists rot mid-season).

## Decisions Confirmed (2026-08-14)

- Apps Script Web App write layer: **approved**.
- Minimum OS: **iOS 26** (was iOS 17+); Xcode 26 toolchain; Foundation Models in scope.
- UI design reference: **Apple Reminders** (see Design Language section).
- Distribution: **TestFlight** under Colin's existing Apple Developer account.
  Colin has an existing TestFlight build/upload process in his Codex or local Claude
  Code tooling on his Mac — U8 reuses that process rather than defining a new one
  (builds and uploads must run on the Mac regardless; agents in remote/Linux sessions
  cannot produce TestFlight builds).
- **Q1 → resolved: yes** — overwrite mode may uncheck previously-recorded attendees;
  the merge/overwrite dialog makes it deliberate.
- **Q2 → resolved: guest names too.** The app captures guest *names*, not just a
  count. The sheet's `+1's` column still receives only the count (no sheet-structure
  change); names are stored in the app's local SwiftData store attached to the
  submission (useful when guests later convert to members — "Add person" can promote
  a known guest). Guest-name history syncs nowhere else for now.
- **Q4 → resolved: View-votes screen.** The OCR parser is tuned for WhatsApp's
  "View votes" detail layout; the one-time coach screen teaches this. A name-less
  poll-card screenshot is detected and prompts the user to grab the votes view.

## Open Questions

None — all resolved 2026-08-14.

---

## High-Level Technical Design

```
┌────────────── iPhone (SwiftUI app) ──────────────┐
│                                                  │
│  RunPicker ──► AttendanceDraft ◄── prefillers    │
│                     │              ├ OCRPrefill  │      Google
│                     ▼              │  (Vision)   │      Apps Script      Google
│              Review & Confirm      └ VoicePrefill│      Web App          Sheet
│                     │                 (Speech)   │   ┌───────────┐   ┌──────────┐
│                     ▼                            │   │ doPost:   │   │ 2026 tab │
│               SyncEngine ── outbox (SwiftData) ──┼──►│ getState  │──►│ (canon-  │
│                     ▲                            │   │ submit…   │   │  ical)   │
│               RosterCache (SwiftData) ◄──────────┼───│ addMember │   └────┬─────┘
└──────────────────────────────────────────────────┘   └───────────┘        │
                                                weekly-data-sync.yml (unchanged)
                                                            │
                                                   public/data/2026.csv → dashboard
```

App layer map (`ios/FCTCAttendance/`):

- `Models/` — `Member`, `Run`, `AttendanceDraft`, `PendingSubmission` (SwiftData).
- `Services/SheetAPI.swift` — typed client for the four actions; `Services/SyncEngine.swift`
  — outbox, retry w/ backoff, conflict surfacing.
- `Intelligence/` — `NameMatcher` (fuzzy + nicknames + ambiguity rules),
  `NameExtractor` protocol with two implementations: `ModelExtractor`
  (FoundationModels guided generation, availability-gated) and `HeuristicExtractor`
  (deterministic fallback); `PollScreenshotParser` (Vision → text lines) and
  `VoiceEntryParser` (transcript) both feed whichever extractor is active. All pure &
  protocol-fronted → unit-testable (heuristics fully; model path behind a seam).
- `Views/` — `RunPickerView`, `ChecklistView` (the Review & Confirm screen),
  `ScreenshotImportView`, `VoiceEntryView`, `OutboxView`, `SettingsView`
  (endpoint URL + secret, device name).

Apps Script layer (`apps-script/`): `Code.gs` (router, auth, LockService),
`SheetOps.gs` (header detection, band mapping, reads/writes, insertions — pure logic
factored from I/O for testing), `appsscript.json`, `.clasp.json`, plus
`test/sheetops.test.js` running the pure functions in Node against repo CSV fixtures.

---

## Implementation Units

Sized for independent coding agents; each has a contract (inputs/outputs/acceptance)
and names its dependencies. U1+U2 are the foundation; U3–U7 parallelize after U2's
contract freezes (mocks let U4–U6 start even earlier).

- **U1 — Repo scaffolding & fixtures.** Create `ios/` (Xcode 26 project, SwiftUI app
  target, **deployment target iOS 26**, unit-test target, SwiftData stack) and
  `apps-script/` (clasp scaffold). Extract shared test fixtures (poll-screenshot
  PNGs — synthetic, WhatsApp-style; transcript strings; CSV snapshots) under
  `fixtures/attendance/`. *Accept:* project builds in Xcode 26, `npm test` still
  green, README section added.
- **U2 — Apps Script API** (the contract everything else depends on). Implement the
  four actions per the table above, port header/band detection from `dataParser.js`,
  LockService serialization, revision hashing, secret check, structured errors. Pure
  sheet-geometry functions live in `SheetOps.gs` and are mirrored/tested in Node
  against 2025 *and* 2026 fixtures (incl. two-runs-one-date, mid-season column
  insert keeping alphabetical order and formulas). *Accept:* Node tests green; manual
  `clasp` deploy to a **copy** of the real sheet passes a scripted smoke run
  (get→submit→re-get roundtrip, conflict path, addMember).
- **U3 — SheetAPI client + SyncEngine + models** (dep: U2 contract, mockable).
  Typed client, SwiftData models, outbox with exponential backoff, conflict → UI
  event. *Accept:* unit tests with a stub server cover success, retry-after-offline,
  idempotent re-submit, conflict surfacing.
- **U4 — Checklist modality + Review & Confirm + run picker** (dep: U3 interfaces).
  Reminders-idiom UI per the Design Language section: home "list of lists",
  grouped-inset checklist with circular check toggles, quick-add "Add person…" row
  (calls `addMember`, optimistic insert), guest entry (names, stored locally; count
  derived for the sheet's `+1's`) and kms detail rows (decimal pad, pre-filled with
  `Approx kms`), default-run selection rule (R7), provenance badges,
  merge/overwrite dialog, outbox screen. *Accept:* UI tests: happy path,
  already-recorded-row warning, offline queue; visual pass against Reminders idioms.
- **U5 — NameMatcher + extractors** (dep: none after U1 — pure Swift). Normalization,
  fuzzy scoring, nickname table, ambiguity rule (near-collision roster names never
  auto-pick), confidence tiers; the `NameExtractor` protocol with `HeuristicExtractor`
  (fully tested) and `ModelExtractor` (FoundationModels guided generation with
  availability check → heuristic fallback). *Accept:* table-driven tests incl. the
  real 2026 roster collisions (`Alex*`, `Dan*`, `Laura*`), OCR-typo and ASR-phonetic
  cases; extractor-selection tests via the availability seam.
- **U6 — Screenshot modality** (dep: U5; U4 for the review handoff). PhotosPicker
  multi-select, Vision OCR pipeline, chrome-line filtering, multi-screenshot union,
  candidate → NameMatcher → draft proposals, one-time coach screen ("screenshot the
  View-votes screen"). *Accept:* fixture PNGs parse to expected name sets; unmatched
  names produce add/map suggestions.
- **U7 — Voice modality** (dep: U5; U4 for handoff). Speech authorization flow,
  on-device transcription, `VoiceEntryParser` (names, "+N guests", distance), live
  transcript UI with re-record. *Accept:* fixture transcripts parse to expected
  drafts; distance/guest extraction tests ("we did eight point seven k").
- **U8 — Hardening & release.** Secret/config screen with QR-import (so Aaron never
  types a URL), app icon, error-state polish, TestFlight build **via Colin's existing
  TestFlight process (Codex or local Claude Code on his Mac — do not invent a new
  pipeline)**, `clasp` production deploy against the real sheet, smoke test on a real
  Friday run, ops notes in README.
  *Accept:* both phones record a real run end-to-end; sheet cells byte-identical in
  the next weekly CSV sync (R11 verified by diffing the synced CSV).

Dependency graph: `U1 → U2 → U3 → U4 → U8`, with `U5 → {U6, U7} → U8`; U5 starts
immediately after U1, U6/U7 join U4's review screen when both exist.

## Agent Orchestration (Fable → Opus / Codex 5.6)

How this plan becomes running code, per Colin's intent to have **Fable orchestrate
Opus and Codex 5.6 solo agents**:

- **Fable (orchestrator).** Runs in this repo's session; owns the plan, sequencing,
  integration, and review. Spawns/coordinates Claude-side agents directly (Agent /
  Workflow tools). **Note:** Codex 5.6 agents run in OpenAI's tooling and cannot be
  spawned from a Claude session — they are engaged by pointing Codex at this repo +
  a work-packet file. To make that seamless, every unit above gets a standalone
  packet at `docs/plans/packets/U<N>.md` (generated at kickoff): contract, files it
  may touch, fixtures, acceptance commands, and "do not touch" list. A packet is
  agent-agnostic — Opus and Codex receive identical briefs.
- **Suggested assignment** (tune to taste): Opus agents on the contract-heavy /
  ambiguity-heavy units (U2 API + sheet geometry, U5 NameMatcher, U8 integration);
  Codex agents on the well-specified UI units (U4, U6, U7) and scaffolding (U1, U3).
  Parallel waves: wave 1 = U1; wave 2 = U2 ∥ U5; wave 3 = U3 ∥ U6-prep ∥ U7-prep;
  wave 4 = U4 ∥ U6 ∥ U7; wave 5 = U8.
- **Branch protocol.** One branch per unit (`feat/attendance-u<N>-<slug>`), PR into an
  integration branch (`feat/attendance-app`), Fable reviews each PR against the
  packet's acceptance list before merge; `main` only receives the integration branch
  when U8 passes. CI addition (part of U1): a workflow job running the Node
  `apps-script` tests and Swift package tests for the pure `Intelligence/` targets
  (full Xcode UI tests stay local/manual — no macOS CI requirement forced on the
  hobby setup).
- **Contract freeze.** U2's API table (above) is the inter-agent interface; any agent
  needing a change PRs the *plan/packet first*, Fable adjudicates, then code. This
  keeps parallel agents from drifting apart on the one seam they share.

## System-Wide Impact

- The dashboard, parser, weekly sync, and Vercel deploy are untouched; the app only
  improves data freshness/accuracy upstream of them.
- New top-level directories `ios/` and `apps-script/` in a formerly web-only repo:
  `.gitignore` gains Xcode/clasp entries (U1); Vercel build is path-scoped already
  (`vite build` reads only web paths) — verified no config change needed.
- The Google Sheet gains a second writer. Write scope is strictly the run-row cells +
  member-band header; the weekly sync's validation (non-HTML, size floors) is
  unaffected. Mid-season member columns added by the app are exactly what the
  schema-tolerant parser was built for.

## Risks & Dependencies

- **Sheet structure drift by human editors** (rows moved, columns reordered) between
  app read and write → mitigated by row-identity verification + revision check +
  conflict UX (R8); the app never writes by blind coordinates.
- **Apps Script quotas/cold starts**: web-app calls can take 1–3 s → UI treats sync as
  async (outbox pattern) so the user never waits on a spinner to leave the screen.
- **WhatsApp UI changes** breaking OCR chrome-filtering → parser is fixture-tested and
  heuristic-only; worst case the user unchecks noise on the Review screen (graceful
  degradation, R4's human-confirm step is load-bearing by design).
- **Shared-secret leakage** → rotate in Script Properties + app settings; endpoint
  does nothing but the four actions on one sheet.
- **Speech/Vision permission denials** → checklist modality is always available;
  modalities are enhancements, never the only path.
- **Foundation Models availability** (device not Apple-Intelligence-capable, model
  not downloaded, or feature disabled) → `ModelExtractor` checks availability per
  request and silently falls back to `HeuristicExtractor`; parsing quality degrades,
  correctness doesn't.
- **Release builds require Colin's Mac** (Xcode 26 + TestFlight upload) — remote
  agents deliver source + green tests; the build/upload step is Colin's existing
  process (confirmed available).

## Phased Delivery

1. **Phase 1 — Canonical write path (U1–U4).** Checklist-only app, real sheet writes,
   outbox, TestFlight. *This alone kills the painful mobile-sheet-editing workflow.*
2. **Phase 2 — Smart pre-fill (U5–U7).** Screenshot and voice modalities land on top
   of the proven Review/sync core.
3. **Phase 3 — Hardening (U8) + deferred items** (Strava kms, notifications, LLM
   fallback) as appetite allows.

## Alternative Approaches Considered

- **Direct Sheets API + Google Sign-In in-app**: rejected — sensitive-scope OAuth
  verification burden / 7-day token expiry in testing mode; heavy for two users.
- **Vercel serverless + service account**: workable fallback if Apps Script ever
  chafes (same JSON contract, so swappable), but adds GCP key management now.
- **PWA instead of native iOS**: would dodge TestFlight, but loses first-class Vision
  OCR, on-device speech, share-sheet screenshot ingestion, and offline robustness —
  the three modalities are exactly the native-strength features.
- **Replacing the sheet with a database + sheet mirror**: explicitly out of scope;
  the sheet *is* the database of record (R1).

## Documentation / Operational Notes

- U8 adds a README section: TestFlight install, secret rotation, new-season
  checklist (new tab → update Apps Script `SEASON_GID` property; app picks up the new
  roster/rows automatically via `getState`).
- Apps Script deploys: `clasp push && clasp deploy` from `apps-script/`; the
  deployment URL is stable across versions (use versioned deployments, update the
  same deployment ID).
- The one-time sheet-copy used for U2 smoke tests should be deleted after Phase 1 to
  avoid a stale near-canonical twin.
