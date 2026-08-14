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

- `public/data/2025.csv` — frozen historical season.
- `public/data/2026.csv` — current season, refreshed weekly by the sync workflow (below).

Years are registered in **`src/config/years.js`**:

```js
export const YEARS = { 2025: '/data/2025.csv', 2026: '/data/2026.csv' }
export const LATEST_YEAR = 2026   // the default view
```

### Adding a future year

1. Drop the new export at `public/data/<year>.csv`.
2. Add one line to `YEARS` in `src/config/years.js` (and it becomes the new `LATEST_YEAR`
   automatically since that is derived from the max key).
3. Point the sync workflow at the new season (see below): bump `CURRENT_YEAR` and `SHEET_GID`.

No other code changes are required — the parser and metrics are schema-tolerant.

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

`.github/workflows/weekly-data-sync.yml` fetches the current season's published CSV from
Google Sheets every **Sunday at 17:17 Australia/Perth** and commits it to
`public/data/<CURRENT_YEAR>.csv` only if it changed. The off-minute start reduces common
schedule congestion. GitHub can still delay a scheduled run during high load. It can also
disable a public repository's schedule after 60 days without repository activity. See the
[GitHub schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
The workflow uses one ordered concurrency group with `queue: max`. GitHub can hold up to 100
pending runs in that group without replacing an earlier pending run. See the
[GitHub concurrency guide](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

Vercel's GitHub integration deploys on push. `workflow_dispatch` is also enabled for
manual/on-demand runs and as the schedule fallback. `scripts/fetch-sheet.sh` fetches and
validates the download. It rejects login/HTML pages, empty bodies, and truncated responses,
so a bad fetch never overwrites good data.

### One-time setup (required before the sync works)

Configure these at the top of `.github/workflows/weekly-data-sync.yml`:

1. **Share the sheet** so the export URL is reachable without auth: either "Anyone with the
   link = Viewer" or "Publish to web". A private sheet returns an HTML login page, which the
   workflow rejects loudly instead of committing garbage.
2. **`SHEET_GID`** — the current-season tab's gid (the number after `gid=` in that tab's
   browser URL). It ships as a `REPLACE_ME` placeholder and the run fails on purpose until set.
3. **`CURRENT_YEAR`** — the season to refresh (e.g. `2026`); bump it (and `SHEET_GID`) each new season.

`SHEET_ID` is already set to the FCTC spreadsheet. The export endpoint used is
`https://docs.google.com/spreadsheets/d/<SHEET_ID>/export?format=csv&gid=<SHEET_GID>`
(a Publish-to-web `/pub?...output=csv` alternative is commented in the workflow).

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
is at least 50%. Members more than three runs away are excluded.

The email shows `Very likely` for a raw chance of at least 80%, `Likely` for at least 50%, and
`Possible` for a one-away member below 50%. It never shows the exact chance. These labels are
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
4. Use the fixed sender `FCTC Milestones <runs@notifications.fctc.cpd.dev>`.
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

## Deployment

Vercel (hobby), SPA rewrites in `vercel.json`. Pushes to the default branch auto-deploy. After
the first deploy of changes, confirm Bot Protection + AI Bot blocking remain enabled in the
Vercel Firewall.

## Reference

- Pre-redesign baseline (look + architecture as of 2025): `docs/reference/2025-dashboard-baseline.md`.
- Redesign plan + implementation units: `docs/plans/2026-05-28-001-feat-fctc-dashboard-2026-redesign-plan.md`.
