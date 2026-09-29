# Attendance fixtures

Shared, language-neutral fixtures for the FCTC Attendance app (plan:
`docs/plans/2026-08-14-001-feat-fctc-attendance-ios-app-plan.md`). Swift tests
(`ios/FCTCAttendanceKitTests`), Node tests (`apps-script/test`) and the web's Vitest
suite all read from here, so an expectation is written down exactly once. The iOS
test bundle copies this whole folder in as a folder reference (`ios/project.yml`),
so a new file here needs no `xcodegen generate`.

Shared guest identities and history now have a v2 contract in
[`guests/README.md`](guests/README.md) and [`guests/contract.json`](guests/contract.json).
The September shared guest plan supersedes the old local-only guest behaviour below.
Legacy voice fixtures remain unchanged: they describe parser output before identity resolution.

Ground rule from `docs/plans/packets/_conventions.md`: **add fixtures freely; never
edit another unit's `*.expected.json` to make your code pass.** If an expectation is
wrong, say so in the PR and let the orchestrator adjudicate.

## Files

| File | What it is |
|---|---|
| `2025.csv`, `2026.csv` | Season CSV snapshots, copied verbatim from `src/test/fixtures/`. Sheet geometry tests (U2) run against these. Do not edit; re-copy from the originals if they ever change. |
| `poll-*.ocr.txt` | The text LINES Vision emits for a WhatsApp poll screenshot, one line per recognized region, in screen order. Input to `PollScreenshotParser` (U6). |
| `voice-*.transcript.txt` | On-device speech transcripts, one utterance per file. Input to `VoiceEntryParser` (U7). |
| `*.expected.json` | The expected parse result for the same-stem input file. |
| `guests/contract.json` | Synthetic shared guest identities, eleven-run history, v2 requests/responses, canonical digests, and conflicts. |
| `2026-09-27/2025.csv`, `2026-09-27/2026.csv` | Dated snapshot of the live sheets on 27 Sep 2026: the 2026 BIRTHDAY row, the 2025 annotation cells ("🛕", "sad face") and 2026's planned rows to December are all present. The club-day and parser tests and the parity fixtures read it. Do not edit; add a new dated folder for a newer snapshot. |
| `parity/2025.json`, `parity/2026.json` | Golden parity fixtures (R28), generated from the dated snapshot by `scripts/build-parity-fixtures.js`. See [Parity fixtures](#parity-fixtures). Do not edit by hand. |

Roster names in every expectation are the **real 2026 sheet header names** (`Alex 👑`,
`Alex Kr`, `Dan B`, `Laura K`, …). `apps-script/test` asserts this mechanically against
`2026.csv`, so a typo in a fixture fails CI rather than a later unit's tests.

## `*.expected.json` schema

Common keys:

- `fixture` — the input file this describes.
- `kind` — `poll-ocr` | `voice-transcript`.
- `season` — which season's roster the expectation is written against.
- `notes` — array of prose lines explaining what the case is testing. Read these
  before changing an expectation.
- `names` — **canonical sheet names to pre-check**, in sheet (alphabetical) order.
  Order is documentation, not a requirement: compare as sets.
- `ambiguous` — `[{ raw, candidates: [sheet name, …] }]`. Near-collision hits that must
  be SUGGESTED and never auto-picked (`Alex 👑`/`Alex B`/`Alex Kr`, `Dan`/`Dan B`,
  `Laura E`/`Laura K`).
- `unmatchedRaw` — raw strings with no acceptable roster match; the UI offers
  "add as new" / "map to existing".

`kind: poll-ocr` adds:

- `isVoteDetailScreen` — `true` for the "View votes" detail screen (has voter names),
  `false` for a poll card in the chat (counts only). A `false` fixture also carries
  `needsVotesView: true` and a `reason`.
- `options` — `[{ label, voteCount, isAffirmative, rawNames }]` in screen order.
  `isAffirmative` marks options that mean "coming" (`Yes`, a day name) as opposed to
  `No`/`Maybe`. **Only affirmative options seed pre-checks** — and even then, poll
  "yes" ≠ attended, so `names` is a proposal the human edits (R4, R6).
- `candidateNames` — every name line found, deduped, in screen order (i.e. before
  matching, across all options).

`kind: voice-transcript` adds:

- `plusOnes` — guest count; `0` means explicitly stated as none, `null` means unstated.
- `distanceKm` — parsed `Actual kms`, or `null` when unstated.
- `guestNames` — guest names when the speaker gave them (historical Q2 parser output).
  The v2 app resolves these labels to shared guest UUIDs before submitting attendance.
  The sheet's `+1's` cell still receives an aggregate count; shared auxiliary tabs retain identities.

## Adding a fixture

1. Drop `<stem>.ocr.txt` / `<stem>.transcript.txt` plus `<stem>.expected.json`.
2. Use only real 2026 roster names in `names`/`ambiguous.candidates`.
3. Run `node --test apps-script/test` — it validates every expected JSON's shape and
   roster spelling.

## Parity fixtures

`parity/<season>.json` is the one contract the web and the iOS app are tested
against (plan `docs/plans/2026-09-28-001-feat-dashboard-review-and-ios-dashboard-plan.md`,
KTD3). The web's own parser and club-day rules write it; Vitest fails when the
committed files drift from them, and the Swift kit tests parse each raw label with
`RunLabel` and recompute `expected` from `runs`.

Each file holds:

- `season`, `clubWeekdays` — the season year and its official club weekdays
  (`src/config/years.js`; 2025 is `["Wed", "Fri"]`).
- `runs` — every recorded run (at least one attendee or +1), by date then sheet
  order: `id`, ISO `date`, sheet `weekday`, the raw `run` and `meet` cells as typed
  (`"**Cruise"`, `"Some-day"`), the normalized `type`, `event` and `location`,
  `actualKm`, sorted `attendees` and `plusOnes`.
- `expected.totals` — `runs`, `memberKm` (actual km × attendees, +1s excluded,
  rounded to 2 decimals after summing) and `runners` (members with a run).
- `expected.members` — per runner, `runs` and `memberKm` (2 decimals).
- `expected.clubDays` — `count` and the ordered ISO `dates`.
- `expected.streaks` — per runner, `current` with `currentFrom`, `best` with
  `bestFrom`/`bestTo` (null when 0; the earlier of two equal bests) and
  `madeByWeekday`.
- `expected.milestones` — the milestone shortlist over that season's totals.

Names sort in plain UTF-16 string order, and every key keeps a fixed position, so a
rule change reads as a small diff.

### Regenerate

```sh
node scripts/build-parity-fixtures.js     # rewrites parity/<season>.json
npx vitest run scripts/build-parity-fixtures.test.js
```

Regenerate after any change to `src/utils/dataParser.js`, `runLabels.js`,
`clubDays.js` or `src/config/years.js`, then read the diff: every changed number is
a rule change the Swift kit must match. For a newer snapshot, add
`fixtures/attendance/<date>/<season>.csv`, point `SNAPSHOT_DIR` in the script at it,
regenerate, and update the spot checks in the test.
