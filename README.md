# FCTC Dashboard

A dashboard for the Filament Coffee Track Club: per-season run stats and attendance, plus a
year-end "Wrapped" retrospective. It is a static React SPA on Vercel, fed by a weekly Google
Sheets export.

Multiple seasons live on one site (2025, 2026, ...). A year control switches between them and
All time. The dashboard is a quick reference, not a story. fctc.fun proxies it at `/dashboard`,
so it uses the hub's Poster brand: crema and espresso paper, pink accents, gold bibs, the sock
stripe and square 2px rules, in light and dark. Wrapped keeps its own look.

## Quick start

```bash
npm install
npm run dev          # Vite dev server
npm run build        # production build to dist/
npm run preview      # serve the build locally
npm run test         # run the Vitest suite once
npm run test:watch   # watch mode
```

## Stack

React 19, Vite 7, React Router 7, PapaParse 5, Vitest + Testing Library. No backend; everything
runs client-side off committed CSVs.

- **Poster styles.** The dashboard and run pages use plain CSS scoped to a `.poster` root:
  brand tokens and layout in `src/styles/poster.css`, chart tokens and chart styles in
  `src/styles/poster-charts.css`. Nothing lands on `:root`, because Wrapped's Tailwind theme
  reuses some of the same token names.
- **Fonts.** Anton (display), Archivo (body) and Space Mono (labels), self-hosted through
  `@fontsource`. Vite emits the files under `/assets/`, which fctc.fun already proxies.
- **Charts.** Hand-rolled SVG React components in `src/components/Dashboard/`, drawn from pure
  builders (see "Metrics + visualizations"). `chartKit.js` holds the shared chart helpers.
  There is no chart library.
- **Theme.** One light or dark choice holds across the hub and the dashboard. An inline script
  in `index.html` reads `localStorage.theme` (else the OS preference) and sets `data-theme` on
  `<html>` before first paint. The header's toggle writes the same key.
- **Wrapped.** Tailwind CSS v4 (CSS-first `@theme` in `src/index.css`), Framer Motion 12, and
  Bricolage Grotesque and DM Sans from Google Fonts.

## Data model

Each season is one CSV in `public/data/<year>.csv`, exported from the source Google Sheet.

- `public/data/2025.csv`: the earlier season, refreshed when historical attendance changes.
- `public/data/2026.csv`: the current season. Both seasons refresh in one weekly snapshot.

Years and their club weekdays are registered in **`src/config/years.js`**:

```js
export const YEARS = { 2025: '/data/2025.csv', 2026: '/data/2026.csv' }
export const LATEST_YEAR = YEAR_LIST[0]           // the newest year: the default view
const CLUB_WEEKDAYS = { 2025: ['Wed', 'Fri'] }    // any other season: Mon, Wed, Fri
```

### Adding a future year

1. Drop the new export at `public/data/<year>.csv`.
2. Add one line to `YEARS` in `src/config/years.js`. It becomes the new `LATEST_YEAR`
   automatically, because that is the newest key.
3. If the season's official club weekdays are not Monday, Wednesday and Friday, add them to
   `CLUB_WEEKDAYS` in the same file and to `weekdaysBySeason` in
   `ios/FCTCAttendanceKit/ViewModels/ClubDays.swift`.
4. Add the year to `ATTENDANCE_EXPORT_YEARS` in `apps-script/AttendanceExport.gs`.
5. Register its sheet ID with shared guest setup, then verify the complete snapshot on a copy.

The parser and metrics discover member columns from each season header.

### The parser (`src/utils/dataParser.js`)

`parseRunData(csvText, year)` is **schema-tolerant**. It finds the header row by content (the
row whose first cell is `Date` and which contains `Run` and `Actual kms`). It derives the member
list from that header: every column between `Actual kms` and `+1's`. It **computes all totals
from the run rows** and never reads the sheet's summary rows, which drift between seasons. Each
member's computed run count matches the sheet's own summary row, and the snapshot tests check
it. A computed km total can differ from a stale summary cell; the computed value is the
trustworthy one.

The parser applies these rules:

- **Attendance.** A member cell counts only when its trimmed value is `x`, in any case. Notes
  such as `-`, `🛕`, `sad face` or `12.30` do not count.
- **Runs.** A run is a row whose first cell is a real run date (`Fri, 3-Jan`) and that has at
  least one attendee or +1. Metadata rows such as `BIRTHDAY` never count.
- **Labels.** `src/utils/runLabels.js` strips sheet footnote markers (`**Cruise` is `Cruise`)
  and normalizes each run into a `type`, an `event` and a `location`. For example, `Half - Xmas`
  becomes type `Half Marathon` with event `Xmas`, and the meet `Some-day` becomes `Someday`. A
  run with an event is a holiday special. Every widget, filter and colour uses the normalized
  names. Wrapped keeps the sheet's label without footnote markers (`runType`).
- **Run ids.** Every run gets a stable id, `YYYY-MM-DD-<slug of the label>`, for example
  `2026-09-25-river-loop`. The date carries the year, so ids stay unique in All time. A second
  run with the same date and label gets `-2`.
- **Upcoming.** Dated rows after the season's latest run with nobody on them go into
  `upcoming`, in date order, each with the id it keeps once it is recorded. They never count as
  runs. The first one is the meta row's next run. A blank row before the latest run is an
  unrecorded run, not an upcoming one.

Output shape (stable contract for the dashboard, `calculations.js`, Wrapped, the milestone email
and the parity fixtures):
`{ runs[], members[], memberTotals{}, leaderboard[], distanceLeaderboard[], totalRuns,
totalClubKm, totalAttendanceInstances, runsByType{}, runsByLocation{}, runsByMonth{},
avgAttendance, upcoming[] }`. Each run carries `id`, `parsedDate`, `dayOfWeek`, `type`, `event`,
`location`, `actualKm`, `attendees` and `plusOnes`, plus the sheet's own `date`, `meet` and
`rawRun` cells and the clean `runType` label. `combineYearData(datasets)` merges seasons into
All time with the same aggregation.

**The same rule in Apps Script.** The iOS app reads the sheet through Apps Script, not the CSVs.
`isAttendedMark` in `apps-script/SheetOps.js` applies the same x-only rule. A change to it
reaches the app only after `clasp push` and `clasp deploy -i <existing-id>`; a plain
`clasp deploy` changes the phone endpoint. The x-only rule of 2026-09-28 needs this redeploy.
See the [Apps Script runbook](apps-script/README.md#deploy-runbook-clasp).

### Club days and streaks (`src/utils/clubDays.js`)

A club day is a date on one of its season's official club weekdays with at least one run.
`clubWeekdays(year)` in `src/config/years.js` holds the table: 2025 ran on Wednesday and
Friday, and every other season runs on Monday, Wednesday and Friday.

- A member makes a club day when they run any run that day. The Half and the 10k on Mon 26 Jan
  2026 are one club day.
- A run on any other day is a special: the Saturday Pub Run, the Sunday Xmas races, 2025's
  Invasion Day Monday. A special never adds to or breaks a streak.
- A member's current streak is the number of consecutive most-recent club days they made. A
  finished season shows its streaks "at season end".
- All time joins the club days of every season in date order, each with its own weekdays. A
  streak that runs to Wed 31 Dec 2025 continues into Fri 2 Jan 2026.

Example: Aaron made every 2026 club day from Wed 26 Aug to Fri 25 Sep and also ran the Sat 5 Sep
Pub Run. His current streak is 14; the Pub Run neither adds to it nor breaks it.

The same file holds the milestone rule. Landmarks come every 50 runs. `milestoneShortlist`
keeps members 10 or fewer runs from their next landmark: the closest 3, plus anyone tied with
3rd. It copies the app's `MilestoneBoard` rule, so the dashboard and the app list the same
people. The weekly email uses its own forecast (see "Weekly milestone emails").

The Swift kit mirrors the label, club-day and milestone rules. The parity fixtures below hold
the two stacks to the same numbers.

### Metrics + visualizations

`src/utils/dashboardMetrics.js` holds pure, unit-tested builders. Each takes a view (one
season, or All time) and, where it compares, the previous season. The components only draw what
the builders return. `calculations.js` stays Wrapped-only.

`src/pages/Dashboard.jsx` shows these sections, in order:

| Section | Component | Data |
|---------|-----------|------|
| Title band: year switcher, then a meta row with the update time, last run and next run | `Poster/SeasonTitle` | parser `runs` and `upcoming`, `public/data/last-updated.json` |
| Headline numbers: runs, km run together, runners and members per run; runs and km compare with the previous season on the same date | `Poster/HeadlineNumbers` | `headline(view, previous)` |
| Marquee band: the totals and the current streak leaders | `Poster/Marquee` | `headline`, `wallModel` rows |
| On a roll: top current streaks, season-best streaks with dates, the streak rule in one sentence | `OnARoll` | `onARoll(view)` |
| Leaderboard: top 10 by runs or by km | `Leaderboard` | parser `leaderboard`, `distanceLeaderboard` |
| The Wall: every active runner against every run, with current streaks and specials marked. Sort by runs, streak or name; "Find yourself" highlights one runner. A grid wider than the screen opens on the latest runs | `TheWall` | `wallModel(view)` |
| Every run: one mark per runner in Monday, Wednesday, Friday and Specials tracks; each track labels its busiest day | `EveryRun` | `everyRunTracks(view)` |
| Vs last year: cumulative member-km against the previous season, with the gap at the latest run. Hidden for All time and the first season | `VsLastYear` | `seasonProgress(view, previous)` |
| Milestones ahead: gold bibs for members near their next 50 all-time runs, the same in every view | `MilestoneBibs` | `milestoneShortlist` over all-time totals |
| Run log: every run, newest first, with type, location, month and search filters | `RunLog` | parser `runs`, `monthAxis(runs)` |

The builders keep these honesty rules:

- Headline numbers and charts always describe the whole selected view. Filters scope only the
  run log, so a filter never changes a headline.
- The run log's filters live in the URL. A run link carries them, Back restores them, and a year
  switch resets them.
- The month filter offers only the months from the first to the latest run month
  (`monthAxis`). All time keeps its seasons apart.
- Km is member-km: each run's actual km once per member who ran it, +1s excluded.
- A same-date comparison matches month and day, so 25 Sep compares with 25 Sep in a leap year
  too. All time never compares.
- Members with no runs in the view are left out of per-member outputs.
- Every chart gives hover and keyboard detail, and prints its key values so it reads without
  hover.

### Parity fixtures

The web and the iOS app apply the same rules, in JavaScript and in Swift. Golden fixtures hold
the two stacks to the same numbers.

- `fixtures/attendance/2026-09-27/<season>.csv`: a frozen snapshot of the live sheets on
  27 Sep 2026. Do not edit it. Put a newer snapshot in a new dated folder.
- `fixtures/attendance/parity/<season>.json`: one contract per season. It holds the season's
  club weekdays, every run with its raw and normalized labels, and the expected totals, member
  totals, club days, streaks and milestones.

`node scripts/build-parity-fixtures.js` writes the JSON files from the snapshot with the web's
own parser and club-day rules. `scripts/build-parity-fixtures.test.js` runs in `npm test`. It
rebuilds the files in memory and fails when the committed files drift from them. The iOS kit
tests (`ios/FCTCAttendanceKitTests/ParityFixtureTests.swift`) read the same files, parse each raw
label with `RunLabel` and recompute `expected` from `runs`.

After a change to `dataParser.js`, `runLabels.js`, `clubDays.js` or `src/config/years.js`,
regenerate and check:

```bash
node scripts/build-parity-fixtures.js
npx vitest run scripts/build-parity-fixtures.test.js
```

Read the diff. Every changed number is a rule change that the Swift kit must match. The schema
is in `fixtures/attendance/README.md`.

## Year switching

The URL query param `?year=YYYY` or `?year=all` drives the selected view (`useSearchParams` in
`src/App.jsx`). An absent or invalid value falls back to `LATEST_YEAR`, so views are shareable.
The title band's year control writes `?year` and drops the run log's filters. The app loads and
parses every season once at start (all the CSVs together are about 26 KB), so a year switch is
instant. The **2025 Wrapped** routes are pinned to 2025 data regardless of the dashboard's
selected year.

## Routes

- `/`, `/dashboard`: the dashboard. The app's own domain serves it at the root, and fctc.fun
  proxies it under `/dashboard`. Every link stays under the mount point it was opened from
  (`src/utils/dashboardPaths.js`).
- `/run/:runId`, `/dashboard/run/:runId`: one run. The run resolves from its id alone, inside
  the season its date names, so a 2025 run opened from All time is that 2025 run. An unknown or
  old numeric id shows "Run not found".
- `/wrapped`, `/wrapped/:member`, `/2025wrapped`, `/2025wrapped/:member`: 2025 Wrapped (pinned
  to 2025).

The query holds `year` (a season or `all`) and the run log's filters: `type`, `location`,
`month` and `q`. A run link keeps the view it was opened from, and the run page's Back link
returns to it:

```text
/dashboard?year=2025&location=Filament                            the view
/dashboard/run/2025-12-31-intervals?year=2025&location=Filament   a run opened from it
```

## Weekly data sync

`.github/workflows/weekly-data-sync.yml` captures every supported season through the
Apps Script endpoint each **Sunday at 17:17 Australia/Perth**. The endpoint holds the
writer lock while it reads the seasons. A pending write blocks the export. This
keeps a promotion's earlier and current season changes in the same snapshot.

`scripts/sync-attendance-snapshot.js` validates the complete response, its content
digest, supported years, sheet geometry, and size before replacing CSV files.
Quoted fields and embedded newlines remain intact. Changed CSVs and their timestamp
are committed together. Unchanged data creates no timestamp change or commit.
Vercel's existing GitHub integration deploys changed commits.

The snapshot read makes at most four attempts for network interruptions, HTTP
429/5xx responses, or a busy workbook. It waits about one, two, then four seconds.
Authentication and invalid data fail immediately. An exhausted retry leaves the
CSV files unchanged and prevents milestone processing from using stale data.

The workflow retains the ordered concurrency group and manual trigger. Notification
processing runs only after a successful sync. The snapshot does not include guest
registry, attendance ledger, or operation tabs.

### One-time setup for shared guest exports

Complete the approved Apps Script upgrade before merging this workflow change.
Follow the [shared guest setup procedure](docs/operators/shared-guest-setup.md)
and its durable request helper. It verifies the deployed v2 reads before setup
and checks saved receipts after an interrupted setup.
Set repository variable **`FCTC_ATTENDANCE_ENDPOINT`** to the stable HTTPS `/exec`
URL. Set repository secret **`FCTC_ATTENDANCE_SECRET`** to the app's shared secret.
The sync step alone receives these values; notification steps do not receive them.
Missing settings fail the sync and prevent notification processing.

Keep the source workbook restricted to authorised organisers. Stop publishing its
auxiliary tabs, and test anonymous access to the workbook before enabling shared
guests. Hiding tabs does not restrict access. The dashboard remains public through
its committed season CSVs; it no longer requires a public source workbook.

For a local check, supply the two settings in your shell environment and run:

```bash
node scripts/sync-attendance-snapshot.js
```

The command changes local CSVs when their contents change. Use a temporary checkout
or pass `root` to the exported function for copy-sheet testing. Keep copy data and
secrets out of commits. `scripts/fetch-sheet.sh` remains available for manual legacy
CSV imports; the weekly workflow does not use it.

## Weekly milestone emails

The same `Weekly Data Sync` workflow checks milestones after the CSV sync. It reads every
season registered in `src/config/years.js` and calculates exact all-time attendance from the
CSV run rows. For each member, it forecasts their next positive multiple of 50 across the
fixed next Monday, Wednesday, and Friday opportunities. The forecast uses all completed
registered-season history through the inclusive cutoff, starting with the member's first
recorded attendance.

The forecast calculates a separate recency-weighted attendance rate for each weekday. Older
history loses half its weight after eight opportunities on the same weekday. It combines the
three rates as an independent three-event approximation. A member who is exactly one run away
is always included. Members who are two or three runs away are included when their raw chance
is at least 15%. Members more than three runs away are excluded.

The email shows `Very likely` for a raw chance of at least 80%, `Likely` for at least 50%, and
`Possible` for any included member below 50%. It never shows the exact chance. These labels are
heuristic. Cancellations, special schedules, and correlated absences can make the fixed
forecast wrong. The same member can qualify again next week if their recorded total does not
change.

The feature creates one branded HTML digest for all candidates and keeps the same plain-text
content as a fallback. It sends a separate copy to each recipient through the
[Resend batch API](https://resend.com/docs/api-reference/emails/send-batch-emails), so
recipients do not see other addresses. The HTML uses inline styles, email-safe fonts, and no
remote images. A normal preview or send with no candidates creates no email and stops before
any Resend request. The feature has no backend, database, or notification history.

The exact CSV header is the member identity across seasons. Keep a member's header text
unchanged. A rename creates a separate identity and splits the all-time total.

### Local preview

Run a production-data preview from the repository root:

```bash
node scripts/send-milestone-digest.js --preview
```

Preview is the default mode. It makes no provider request. A local preview needs no GitHub
output files, GitHub credentials, Resend credentials, or recipient secrets.

### One-time GitHub and Resend setup

1. Create the GitHub environment `milestone-production`. Allow only the `main` branch. See
   [GitHub environment setup](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).
2. Add these environment secrets: `RESEND_API_KEY`, `MILESTONE_RECIPIENTS`, and
   `MILESTONE_SMOKE_RECIPIENT`. The smoke recipient must be Colin's address.
3. Add the repository variable `MILESTONE_EMAIL_ENABLED`. Set it to `false` first.
4. Use the fixed sender `FCTC Delivery Service <runs@notifications.fctc.cpd.dev>`.
5. Add `notifications.fctc.cpd.dev` in Resend. Add the supplied DNS records to Cloudflare,
   then wait for Resend to mark the domain as verified. See the
   [Resend domain guide](https://resend.com/docs/dashboard/domains/introduction).
6. Keep open and click tracking disabled. Resend documents that both are disabled by
   default. Verify the settings before activation. See the
   [Resend tracking guide](https://resend.com/docs/dashboard/domains/tracking).
7. Create a sending-access API key. Restrict it to `notifications.fctc.cpd.dev`. Limit Resend
   team access, then save the key as `RESEND_API_KEY`. See the
   [Resend API key guide](https://resend.com/docs/dashboard/api-keys/introduction).

Set `MILESTONE_RECIPIENTS` to comma-separated single mailbox addresses. Do not use display
names. The script trims, case-insensitively deduplicates, and sorts the addresses. It accepts
at most 100 valid addresses. Keep the configured count below 101.

Resend retains email data for 30 days across standard plans. Operators must account for
member names in provider data and limit provider access. See Resend's
[data retention note](https://resend.com/docs/dashboard/webhooks/how-to-store-webhooks-data).

### Manual modes and logs

Run the workflow from the GitHub Actions page and select `notification_mode`:

- `preview` is the default. It reads no email secrets and makes no provider request.
- `send` needs an enabled gate, at least one candidate, `main`, and both `github.actor` and
  `github.triggering_actor` set to `cpdis`.
- `smoke` sends fixed `[TEST]` text and sample HTML only to `MILESTONE_SMOKE_RECIPIENT`.
  It uses one fictional runner and reads no attendance data. It needs `main` and both actors
  set to `cpdis`, but it does not need the enable gate. Each workflow run uses a new smoke
  idempotency key, so a rerun after a configuration fix reaches Resend.

A re-run of a scheduled workflow never sends email. Use a new manual `send` dispatch when a
live retry is required. An unauthorized manual send stays provider-free and reports refusal.

An `accepted` result means that Resend accepted each batch item. It does not prove inbox
delivery. Use the Resend dashboard and the recipient inbox to prove delivery.

Public logs and the job summary may contain only the mode, target week, candidate count,
recipient count, accepted item count, sanitized provider status, and a fixed error category.
They must not contain names, addresses, message content, API keys, provider IDs, or raw
provider responses.

### Activation checklist

Keep `MILESTONE_EMAIL_ENABLED=false` until all checks pass:

- Run the full tests and production build.
- Confirm the Resend domain is verified and tracking is disabled.
- Confirm the API key has sending access only and is restricted to the verified domain.
- Confirm the fixed sender and every recipient. Use 100 or fewer recipient addresses.
- Save a production-data preview with its target week and candidate count.
- Run the fixed smoke mode. Confirm the branded sample is accepted and reaches Colin's inbox.
- Inspect the public logs and confirm they contain no private data.

Set `MILESTONE_EMAIL_ENABLED=true` only after the checklist passes.

### First Sunday checks

Before the run, save the expected target week, candidate count, and recipient count. Within
15 minutes after completion, compare the sync result, mode, counts, and accepted count with
those values. A zero-candidate run must create no Resend batch. Check the Resend dashboard
and recipient inboxes. Check delivery and bounce status again the next morning.

Disable delivery after any count mismatch, workflow failure, bounce, complaint, privacy
leak, or incorrect content.

### Retries, disable, and recovery

Provider requests have a 10-second timeout for headers and response content. They have at
most three attempts. The notify job also has a 10-minute limit. The script retries temporary
failures only. It reuses the weekly idempotency key, which Resend retains for 24 hours. See
the [Resend idempotency guide](https://resend.com/docs/dashboard/emails/idempotency-keys).

Do not start a manual live send while a scheduled run is queued or running. Keep the gate
enabled for one controlled same-week retry. Disable it after a repeated failure. After 24
hours, inspect Resend before a retry because an ambiguous earlier request might have sent.

To stop delivery, set `MILESTONE_EMAIL_ENABLED=false` first. Cancel a queued or running
notification workflow. Revoke the Resend key only after a suspected leak or when an
in-flight send cannot otherwise stop. Preserve the CSV sync. An accepted email cannot be
recalled. Send a correction if its content is wrong.

### Recipient and key maintenance

To add, remove, or replace a recipient, set the gate to `false`, replace the complete
`MILESTONE_RECIPIENTS` secret, and validate the address count and format. Change
`MILESTONE_SMOKE_RECIPIENT` separately when Colin's mailbox changes. Re-enable the gate only
after the intended list is confirmed.

To rotate the provider key, set the gate to `false`. Create a new sending-access key for the
verified domain. Replace `RESEND_API_KEY`, run the fixed smoke test, and confirm receipt.
Revoke the old key, then re-enable the gate.

## Attendance app

A native iOS app (SwiftUI, iOS 26) for recording attendance and actual kms right after a run.
Record a run by hand, from a WhatsApp poll screenshot (on-device OCR), or by voice. The app
writes straight back into the **same Google Sheet this dashboard reads**. The sheet stays the
canonical record. The app is a new *writer*, and this dashboard's weekly sync, parser and
build are untouched by it.

- `ios/`: the app. The Xcode project is generated, not committed:
  `cd ios && xcodegen generate` (XcodeGen reads `ios/project.yml`). All non-UI logic
  lives in the `FCTCAttendanceKit` framework so it is unit-testable.
- `apps-script/`: the Google Apps Script Web App the phone posts to (JSON + shared
  secret, no OAuth in the app). Runbook: `apps-script/README.md`.
  Tests: `node --test apps-script/test`.
- `fixtures/attendance/`: shared fixtures (season CSV snapshots, golden parity fixtures,
  OCR line dumps, voice transcripts + expected parse results). Schema:
  `fixtures/attendance/README.md`.

Plans: the app (architecture, API contract, design language, work units) is in
`docs/plans/2026-08-14-001-feat-fctc-attendance-ios-app-plan.md`. The tab bar, Events and
Dashboard are in `docs/plans/2026-09-28-001-feat-dashboard-review-and-ios-dashboard-plan.md`.

### Tabs

The app opens on a Liquid Glass tab bar with three tabs
(`ios/FCTCAttendance/Views/RootTabView.swift`):

- **Runs**: the This Week and Unsynced tiles, today's run, Season and Past Runs. Record
  attendance here.
- **Events**: what is coming up (see "Events tab").
- **Dashboard**: the web dashboard's quick reference, drawn natively (see "Dashboard tab").

Each tab keeps its own navigation stack. The run picker and the checklist hide the tab bar,
so their bottom-bar search and Review button stay reachable. A reminder tap or an App Intent
route always lands on Runs. The app selects Runs, pops it to its root and opens the checklist.
The other tabs keep their stacks. A new connection (for example, a scanned setup code) returns
every tab to its root.

The app keeps its Reminders look on every tab: system colours, the accent the user picks in
Settings, and SF Pro. Dashboard numbers use SF Pro Rounded bold. The web's Poster brand stays
on the web.

### Events tab

Events reads the offline cache, so it works without a network. The kit's `EventsBoard` builds
four lists:

- **This week**: the club runs from today to Sunday, on the Perth calendar.
- **Specials**: upcoming runs off a club weekday, or with an event in the label. The runs on
  one date fold into one row with their options, for example "Xmas: Mara / Half / 10k". A
  holiday special on a club weekday shows here, and it still counts as a club day for streaks.
- **Milestones**: the members closest to their next 50 all-time runs.
- **Birthdays**: today and the next 30 days.

Each list has an empty line, for example "No specials scheduled."

**Milestones** is the passive counterpart to the weekly emails above. Both use the same
definition of a landmark (the next positive multiple of 50) and the same attendance rule (only
an `x` counts; see "The parser"). They agree on every total once the current Apps Script is
deployed. They differ in what they show. The email forecasts who is *likely* to get there this
week and only considers people within three runs. The app lists the closest few with the runs
they need, and makes no forecast. An all-time total is the member's runs before this season
plus this season's runs, unsynced check-ins included. So the app reflects attendance recorded
seconds ago, even offline. The email reads the weekly CSV export.
See `docs/plans/2026-08-16-001-feat-milestones-ahead-section-plan.md`.

**Birthdays** follows Milestones. It orders the rows by days remaining, then name, on Perth
calendar dates. The sheet's `BIRTHDAY` row supplies day and month; no birth year or age is
stored. A 29 February birthday shows on 28 February in non-leap years, and keeps its recorded
date. Refreshed birthdays stay available offline. Older Apps Script versions still work; the
birthday field appears after the updated script is deployed.
See `docs/plans/2026-09-18-attendance-count-birthdays-plan.md`.

### Dashboard tab

The Dashboard shows the active season. The cards follow the approved mockup
(`docs/reference/2026-09-28-dashboard-mockups/ios.html`), top to bottom:

- **Headline**: runs this season, or km together, with a Runs/Km toggle. It compares with last
  season on the same date ("+2 runs on 2025 by this date"). Its bars show runners per run for
  the last 24 runs.
- **Together** (member-km, against last season) beside **On a roll** (the longest current
  club-day streak and its runner).
- **The Wall**: runners against the runs of the last five weeks. Open it for the full Wall,
  which scrolls sideways, opens at the latest run, and sorts by runs, streak or name.
- **Vs last year**: cumulative member-km against last season, on a Jan to Dec axis.
- **Every run**: runners per run for the last 18 runs. Guests stack on top in a lighter shade.
- **Leaderboard**: by runs or by km.
- **Run log**: every run, newest first, grouped by month. Search matches the run type, event,
  place or a runner.

Tap a runner (On a roll, a Wall name or cell, a leaderboard row, a run's runners) to open the
**runner screen**. It shows runs, km, the current streak and rank, a season calendar of club
days with the streak marked, club days made per weekday, and all-time runs with progress to
the next milestone.

The views live in `ios/FCTCAttendance/Views/Dashboard/`. The kit's `DashboardModel` builds every
card, and `DashboardStore` decides when to rebuild it.

### Where the numbers come from

Events and the Dashboard compute every number on the phone, from the cached season. They work
offline. `ios/FCTCAttendance/ActiveSeason.swift` gives both tabs the same inputs:

- **Effective runs.** `EffectiveRuns` applies the outbox to the cached runs, oldest first.
  Each submission replays its endpoint's own write path (the legacy merge or overwrite, or the
  shared guest plan), so the result equals the sheet after sync. A check-in recorded offline
  moves streaks, totals and milestones at once, and the headline says "Includes N unsynced".
- **Lifetime priors.** `LifetimePriors` turn the sheet's lifetime totals into runs before this
  season. An all-time total is the prior plus this season's effective runs.
- **Last season.** It comes from a read-only snapshot. `SyncEngine.previousSeasonSnapshot()`
  fetches the previous supported season once and stores only its cache row. It never changes
  the live season, the run cache or the reminders. A legacy endpoint has no earlier season, so
  Vs last year and the same-date comparisons stay hidden. Offline, before the first fetch, the
  card reads "Last season not downloaded".
- **Rules.** `RunLabel`, `ClubDays`, `MilestoneBoard` and `DashboardModel` are the Swift mirror
  of the web's rules. The parity fixtures hold both stacks to the same numbers (see "Parity
  fixtures").

Each tab rebuilds its model only when a cheap fingerprint of its inputs changes. A render never
fetches or decodes the cache.

The checklist's streak line uses the same club-day rule and effective runs. It reads "N club
days in a row".

### Recording attendance

The **Attendance** heading shows the number of checked members across the full
draft, even during a search. When guests are present, a second line shows the total
people, including named and unnamed guests. Both counts update as the draft changes.

Screenshot and voice entry pre-check a member only on a sure match: an exact name, a
nickname, or one wrong letter in a name of seven or more letters. A close but different
name, such as "Tony" for `Toby`, is only a suggestion. Voice entry ignores a word at the
start of a sentence unless it is a roster name or a nickname. A poll option with a
negative word, such as "Can't make it", pre-checks nobody.

On a run's **Guests** screen, **Name a guest** assigns a saved person or a new
name to one unnamed guest. The total stays the same. Swipe a selected guest to
replace the person. Both search fields support keyboard dismissal while scrolling.
Use **Correct name** in the guest history to save a shared name without syncing the
run. A name change that needs review opens the saved name beside the proposed
correction. Choose **Save name** or **Keep saved name**. Pending changes stay in
Outbox until their original save is confirmed. A queued change shows its saved
error. Delayed reads cannot replace a newer confirmed guest name.

Motion comes from one shared vocabulary in `ios/FCTCAttendance/Views/Motion.swift`.
Frequent actions such as checks and counts get fast, quiet feedback. Rare moments,
such as the first appearance of the Runs tab or the Dashboard cards, may take longer.
Reduce Motion keeps fades and color changes and removes travel and scale.

While a sync runs, the Outbox shows the system spinner in place of Retry and beside
each row it is sending or checking, and the Runs tab's **Unsynced** tile turns its arrows.
The signal comes from the sync engine itself, so it covers automatic syncs after a
confirm as well as a manual Retry. A row whose last send had an unknown outcome reads
"Checking saved changes" until the next sync checks its receipt.

### UI tests and the screen tour

Run the UI tests on the iPhone 17 Pro simulator:

```bash
cd ios && xcodebuild test -project FCTCAttendance.xcodeproj -scheme FCTCAttendance -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FCTCAttendanceUITests -collect-test-diagnostics never
```

`-collect-test-diagnostics never` skips the verbose diagnostics (like a sysdiagnose) that
xcodebuild collects after a failure. That step can take minutes. A whole-target run can skip a
test that was just added; if the count is short, build again and rerun.

Every UI test launches with `-ui-testing`, which replaces the sheet with an in-memory fake
(`ios/FCTCAttendance/UITestSupport.swift`). More launch flags choose the fixture:

| Flag | Sets up |
|------|---------|
| `-ui-shared-guests` | The shared (API v2) fake with this season and last (`UITestSharedGuestAPI.swift`). |
| `-ui-offline` | No automatic outbox drain, so a queued row stays queued until Retry. |
| `-ui-events` | Planned club runs from tomorrow to the Sunday after next, plus three Xmas races on one date. |
| `-ui-dashboard` | A season of 30 club days with fixed streaks: Aaron 14, Col 10, Dan 2 (`UITestDashboardFixture.swift`). |
| `-ui-last-season-offline` | Last season's fetch fails, so Vs last year reads "Last season not downloaded". |

`-ui-events`, `-ui-dashboard` and `-ui-last-season-offline` need `-ui-shared-guests`.

A test cannot tap a notification or scan a setup code. With `-ui-testing` on, the app takes
these links instead (`UITestSupport.handleHook`):

- `fctc-attendance://ui-test/route/today-checklist`: a "today's checklist" route arrives.
- `fctc-attendance://ui-test/route/missing-run`: a route arrives for a run the sheet does not
  have. It can never resolve.
- `fctc-attendance://ui-test/swap-engine`: a connection change replaces the engine.

Open a hook with `XCUIDevice.shared.system.open(url)`, not `app.open(url)`. `app.open`
relaunches the app and loses the tab and stack state under test. On iPhone, tab buttons can
ignore accessibility identifiers, so the tests' tab helper tries the identifier, then the tab
index.

For a visual before/after review, run the opt-in screen tour. It visits the three tab roots
and each main screen with synthetic data, and attaches one screenshot per screen:

```bash
cd ios && TEST_RUNNER_FCTC_SCREEN_TOUR=1 xcodebuild test -project FCTCAttendance.xcodeproj -scheme FCTCAttendance -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FCTCAttendanceUITests/ScreenTourUITests -resultBundlePath ../review/tour.xcresult
```

Export the shots with `xcrun xcresulttool export attachments --path ../review/tour.xcresult --output-path ../review/tour`.
The tour captures the simulator's current appearance. Run it again after
`xcrun simctl ui booted appearance dark` for dark shots. The tour uses the legacy fake, so
Events and the Dashboard show little data. The default test run skips the tour.

### Sheet rules and releases

A birthday row below the attendance header does not count as a run. Keep its Date
cell blank. Shared run IDs follow row insertions; older connections ask for a
refresh if their saved row coordinate no longer matches the run.

Release operations live in `docs/plans/packets/U8-release-runbook.md`. Keep one
production Apps Script deployment ID and update it with `clasp deploy -i`; a plain
deploy changes the phone endpoint. Generate private setup pages with
`apps-script/make-setup-qr.js`. The code is a `fctc-attendance://setup?…` link the app
claims, so scanning it with the iPhone Camera opens the app and asks the person to
confirm before connecting. Every Apps Script endpoint shares one host, so the prompt
shows the deployment ID (for example `AKfy…x9Qc`) and the device name. If the code
points at a different sheet, the prompt says it replaces the current connection and
counts the waiting submissions that stay in Outbox for review. The app validates
HTTPS setup payloads and stores the shared secret in Keychain. For a new season, add
the sheet tab and change the `SEASON_SHEET_NAME` script property; each phone refreshes
itself through `getState`.

## Deployment

Vercel (hobby), with SPA rewrites and cache headers in `vercel.json`. Pushes to the default
branch auto-deploy. fctc.fun serves the same deployment at `/dashboard` through the hub's own
rewrite (see "Routes"). After the first deploy of changes, confirm Bot Protection + AI Bot
blocking remain enabled in the Vercel Firewall.

## Reference

- Approved dashboard mockups, web and iOS (open `index.html`): `docs/reference/2026-09-28-dashboard-mockups/`.
- Dashboard rebuild plan (shared rules, Poster dashboard, iOS tabs): `docs/plans/2026-09-28-001-feat-dashboard-review-and-ios-dashboard-plan.md`.
- Pre-redesign baseline (look + architecture as of 2025): `docs/reference/2025-dashboard-baseline.md`.
- Earlier 2026 redesign plan, superseded by the Poster rebuild: `docs/plans/2026-05-28-001-feat-fctc-dashboard-2026-redesign-plan.md`.
