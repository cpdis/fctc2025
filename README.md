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
Google Sheets every **Sunday 09:00 UTC (~7pm AEST / 8pm AEDT)** and commits it to
`public/data/<CURRENT_YEAR>.csv` only if it changed. Vercel's GitHub integration deploys on
push. `workflow_dispatch` is also enabled for manual/on-demand runs (and as a fallback if
GitHub auto-disables the schedule after 60 days of repo inactivity). `scripts/fetch-sheet.sh`
fetches and validates the download, rejecting login/HTML pages, empty bodies, and truncated
responses so a bad fetch never overwrites good data.

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

## Deployment

Vercel (hobby), SPA rewrites in `vercel.json`. Pushes to the default branch auto-deploy. After
the first deploy of changes, confirm Bot Protection + AI Bot blocking remain enabled in the
Vercel Firewall.

## Reference

- Pre-redesign baseline (look + architecture as of 2025): `docs/reference/2025-dashboard-baseline.md`.
- Redesign plan + implementation units: `docs/plans/2026-05-28-001-feat-fctc-dashboard-2026-redesign-plan.md`.
