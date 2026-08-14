# Attendance fixtures

Shared, language-neutral fixtures for the FCTC Attendance app (plan:
`docs/plans/2026-08-14-001-feat-fctc-attendance-ios-app-plan.md`). Swift tests
(`ios/FCTCAttendanceKitTests`) and Node tests (`apps-script/test`) both read from
here, so an expectation is written down exactly once.

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
- `guestNames` — guest names when the speaker gave them (resolved Q2). The sheet's
  `+1's` column still receives only the count; names stay on-device.

## Adding a fixture

1. Drop `<stem>.ocr.txt` / `<stem>.transcript.txt` plus `<stem>.expected.json`.
2. Use only real 2026 roster names in `names`/`ambiguous.candidates`.
3. Run `node --test apps-script/test` — it validates every expected JSON's shape and
   roster spelling.
