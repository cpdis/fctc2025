---
title: "feat: Been a while card on the iOS Dashboard"
type: feat
status: active
date: 2026-11-23
---

# Been a while card (iOS Dashboard)

## Why

Grant asked on 23 Nov 2026 for a "been a while…" view: members who ran at least
once in the last 12 weeks but not in the last 4, so organisers can nudge them.

## Decisions (Colin, 23 Nov 2026)

- iOS only. The web dashboard is public; a list of named absentees stays in the
  organisers' app. HANDOFF records the card as iOS-only.
- Weeks are days back from today, in Perth. Any run counts, specials included.
  - Recent: a run on or after today − 28 days. A run exactly 28 days ago is recent.
  - Window: a run on or after today − 84 days. A run exactly 84 days ago is in it.
  - Listed: the latest run is in the window and before the recent cut.
- Members only, any run in the window. Guests are +1 counts, not people.
- The live season view only. Hidden when nobody qualifies.

Real data on Mon 23 Nov 2026 (`public/data/2026.csv`): Liam (Fri 23 Oct, 5 runs
in the window), Jack (Wed 2 Sep, 1), Rhys and Laura E (Sat 5 Sep, 1 each).

## Rule (kit, `BeenAWhile`)

```text
today = Mon 23 Nov 2026
window from Mon 31 Aug ─────────── recent from Mon 26 Oct ── today
   Jack  x (Wed 2 Sep)                                      -> listed, 11 weeks
   Liam      x  x  x  x  x (last Fri 23 Oct)                -> listed, 4 weeks
   Aaron     x  x  x  x  x  x  x  x  x  x  x  x  x (Mon 26 Oct) -> recent, not listed
   Ben  x (Sun 30 Aug, 85 days)                             -> outside, not listed
```

- Input: the live season's effective runs (outbox applied) plus every earlier
  season the store has loaded (`history`), so in January the window reaches into
  December. The live roster filters names when it is known: someone on last
  season's sheet only has left.
- Output rows: name, last run date, whole weeks since it, runs in the window.
  Order: the latest last run first, then name (code-unit order, as elsewhere).
- `DashboardStore.beenAWhile` holds it. The store takes a clock (`now`), builds
  the list on each data change and history load, and `advanceDay()` rebuilds it
  only when the Perth day changed (the Dashboard calls it on appear and when the
  app becomes active), so a phone left open overnight moves on.

## Card (app)

Three working options first (row content, placement), screenshots light and dark
in `review/been-a-while.html`. Colin picks one; the other two are deleted. Each
row opens the runner screen.

## Tests

- Kit `BeenAWhileTests`: boundary pairs (28 days ago is recent, 29 is listed;
  84 is listed, 85 is not), specials count, roster filter, January across
  seasons, order, run count, empty list.
- Kit `DashboardStoreTests`: built from the live season, uses loaded history,
  `advanceDay` moves the list, empty on a season with no runs in the window.
- UI `DashboardUITests`: `-ui-dashboard` fixture lists Dan B (last run about
  8 weeks back) and not Aaron; a row opens his runner screen; the card is absent
  on an earlier season.

## Out of scope

- The web dashboard. Named guests. Push or reminder nudges.
- A TestFlight build: build 19 is in flight on `release/testflight-build-18`
  (cpdis/fctc2025#25); any build of this is 20 or later, after that merges.
