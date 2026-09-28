# FCTC Dashboard

A dashboard for the Filament Coffee Track Club: per-season run stats, attendance, and
high-density visualizations, plus a year-end "Wrapped" retrospective. Built as a static
React SPA, deployed on Vercel, fed by a weekly Google Sheets export.

Multiple seasons live on one site (2025, 2026, ...), switchable via a year control. The
dashboard restyle follows a clean, minimal aesthetic with Tufte-minded charts (high
data-ink ratio, no chartjunk, sparklines, small multiples, direct labels).

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

React 19, Vite 7, Tailwind CSS v4 (CSS-first `@theme` in `src/index.css`), Recharts 3,
Framer Motion 12, React Router 7, PapaParse 5, `react-activity-calendar` (calendar heatmap),
Vitest + Testing Library. No backend; everything runs client-side off committed CSVs.

## Data model

Each season is one CSV in `public/data/<year>.csv`, exported from the source Google Sheet.

- `public/data/2025.csv` — earlier season, refreshed when historical attendance changes.
- `public/data/2026.csv` — current season. Both seasons refresh in one weekly snapshot.

Years are registered in **`src/config/years.js`**:

```js
export const YEARS = { 2025: '/data/2025.csv', 2026: '/data/2026.csv' }
export const LATEST_YEAR = 2026   // the default view
```

### Adding a future year

1. Drop the new export at `public/data/<year>.csv`.
2. Add one line to `YEARS` in `src/config/years.js` (and it becomes the new `LATEST_YEAR`
   automatically since that is derived from the max key).
3. Add the year to `ATTENDANCE_EXPORT_YEARS` in `apps-script/AttendanceExport.gs`.
4. Register its sheet ID with shared guest setup, then verify the complete snapshot on a copy.

The parser and metrics discover member columns from each season header.

### The parser (`src/utils/dataParser.js`)

`parseRunData(csvText, year)` is **schema-tolerant**: it finds the header row by content
(the row whose first cell is `Date` and which contains `Run` / `Actual kms`), derives the
member list dynamically (every column between `Actual kms` and `+1's`), and **computes all
totals from the run rows** rather than trusting the sheet's summary rows (which drift between
seasons and have been observed misaligned). This is why a member's computed km can differ
from a stale summary cell in the sheet; the computed value is the trustworthy one. Run counts
reconcile exactly.

Output shape (stable contract consumed by the dashboard, `calculations.js`, and Wrapped):
`{ runs[], members[], memberTotals{}, leaderboard[], distanceLeaderboard[], totalRuns,
totalClubKm, totalAttendanceInstances, runsByType{}, runsByLocation{}, runsByMonth{}, avgAttendance }`.

### Metrics + visualizations

`src/utils/dashboardMetrics.js` holds pure, unit-tested derivations that power the new charts
(kept separate from rendering and from the Wrapped-only `calculations.js`):

| Function | Powers |
|----------|--------|
| `cumulativeSeries(runs)` | `viz/SeasonProgress` (cumulative season line) |
| `runFrequencyByDate(runs)` | `viz/CalendarHeatmap` (GitHub-style run calendar) |
| `memberMonthlyAttendance(data)` | `viz/SparklineLeaderboard` (per-member sparkline table) |
| `firstVsSecondHalf(data)` | `viz/HalfSeasonSlopegraph` (who's showing up more/less) |
| `runTypeMonthlyCounts(data)` | `viz/RunTypeSmallMultiples` (seasonality) |
| `rankByMonth(data)` | reserved for a future bump chart |

These are honest about partial seasons: the slopegraph splits at the *actual* data midpoint
(not a hardcoded month), date-keyed series only include real run dates, and zero-attendance
members are excluded. Shared, decluttered chart defaults live in `src/utils/chartConfig.js`;
reusable SVG primitives (`Sparkline`, `Slopegraph`, `DotPlot`) live in `src/components/Dashboard/viz/`.

## Year switching

The selected year is driven by the URL query param `?year=YYYY` (`useSearchParams` in
`src/App.jsx`), defaulting to `LATEST_YEAR` when absent/invalid, so views are shareable. The
Header's segmented control just sets `?year=`. The **2025 Wrapped** routes are pinned to 2025
data regardless of the dashboard's selected year.

## Routes

- `/`, `/dashboard` — dashboard (honors `?year`)
- `/run/:runId` — single run detail
- `/wrapped`, `/wrapped/:member`, `/2025wrapped`, `/2025wrapped/:member` — 2025 Wrapped (pinned to 2025)

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

A native iOS app (SwiftUI, iOS 26) for recording attendance and actual kms right after
a run — manually, from a WhatsApp poll screenshot (on-device OCR), or by voice — writing
straight back into the **same Google Sheet this dashboard reads**. The sheet stays the
canonical record; the app is a new *writer*, and this dashboard's weekly sync, parser and
build are untouched by it.

- `ios/` — the app. The Xcode project is generated, not committed:
  `cd ios && xcodegen generate` (XcodeGen reads `ios/project.yml`). All non-UI logic
  lives in the `FCTCAttendanceKit` framework so it is unit-testable.
- `apps-script/` — the Google Apps Script Web App the phone posts to (JSON + shared
  secret, no OAuth in the app). Runbook: `apps-script/README.md`.
  Tests: `node --test apps-script/test`.
- `fixtures/attendance/` — shared fixtures (season CSV snapshots, OCR line dumps, voice
  transcripts + expected parse results). Schema: `fixtures/attendance/README.md`.

Plan (architecture, API contract, design language, work units):
`docs/plans/2026-08-14-001-feat-fctc-attendance-ios-app-plan.md`.

The app's home screen also carries a **Milestones** section, which is the passive
counterpart to the weekly emails above. Both use the same definition of a landmark
(the next positive multiple of 50) and the same attendance rule (any mark except
blank and `-`), so they never disagree about a total. They differ in what they show:
the email forecasts who is *likely* to get there this week and only considers people
within three runs, while the app just lists the closest few with the runs they need,
no forecast. The app reads live from the sheet through `getState`, so it reflects
attendance recorded seconds ago; the email reads the weekly CSV export.
See `docs/plans/2026-08-16-001-feat-milestones-ahead-section-plan.md`.

The **Attendance** heading shows the number of checked members across the full
draft, even during a search. When guests are present, a second line shows the total
people, including named and unnamed guests. Both counts update as the draft changes.

Screenshot and voice entry pre-check a member only on a sure match: an exact name, a
nickname, or one wrong letter in a name of seven or more letters. A close but different
name, such as "Tony" for `Toby`, is only a suggestion. Voice entry ignores a word at the
start of a sentence unless it is a roster name or a nickname. A poll option with a
negative word, such as "Can't make it", pre-checks nobody.

The **Birthdays** section follows Milestones. It shows today through 30 days ahead,
ordered by days remaining then name, using Perth calendar dates. The sheet's
`BIRTHDAY` row supplies day and month; no birth year or age is stored. A 29 February
birthday is shown on 28 February in non-leap years, retaining its recorded date.
Refreshed birthdays remain available offline. Older Apps Script versions still
work; the birthday field appears after the updated script is deployed.
See `docs/plans/2026-09-18-attendance-count-birthdays-plan.md`.

On a run's **Guests** screen, **Name a guest** assigns a saved person or a new
name to one unnamed guest. The total stays the same. Swipe a selected guest to
replace the person. Both search fields support keyboard dismissal while scrolling.
Use **Correct name** in the guest history to save a shared name without syncing the
run. A name change that needs review opens the saved name beside the proposed
correction. Choose **Save name** or **Keep saved name**. Pending changes stay in
Outbox until their original save is confirmed. A queued change shows its saved
error. Delayed reads cannot replace a newer confirmed guest name.

A birthday row below the attendance header does not count as a run. Keep its Date
cell blank. Shared run IDs follow row insertions; older connections ask for a
refresh if their saved row coordinate no longer matches the run.

Release operations live in `docs/plans/packets/U8-release-runbook.md`. Keep one
production Apps Script deployment ID and update it with `clasp deploy -i`; a plain
deploy changes the phone endpoint. Generate private setup pages with
`apps-script/make-setup-qr.js`. The code is a `fctc-attendance://setup?…` link the app
claims, so scanning it with the iPhone Camera opens the app and asks the person to
confirm the endpoint before connecting. The app validates HTTPS setup payloads and
stores the shared secret in Keychain. For a new season, add the sheet tab and change the
`SEASON_SHEET_NAME` script property; each phone refreshes itself through `getState`.

## Deployment

Vercel (hobby), SPA rewrites in `vercel.json`. Pushes to the default branch auto-deploy. After
the first deploy of changes, confirm Bot Protection + AI Bot blocking remain enabled in the
Vercel Firewall.

## Reference

- Pre-redesign baseline (look + architecture as of 2025): `docs/reference/2025-dashboard-baseline.md`.
- Redesign plan + implementation units: `docs/plans/2026-05-28-001-feat-fctc-dashboard-2026-redesign-plan.md`.
