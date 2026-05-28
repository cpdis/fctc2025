---
title: "feat: FCTC Dashboard 2026 — multi-year support, Tufte-grade clean redesign, automated weekly sync"
type: feat
status: active
date: 2026-05-28
---

# feat: FCTC Dashboard 2026 — multi-year support, Tufte-grade clean redesign, automated weekly sync

## Summary

Evolve the single-year (2025) FCTC dashboard into a multi-year site: rewrite the brittle CSV parser to tolerate the 2026 schema (3 new members, shifted header rows), add a year switcher so 2025 and 2026 coexist, and restyle the dashboard toward a clean minimal aesthetic that also honors Edward Tufte's data-viz principles (high data-ink ratio, no chartjunk, small multiples, sparklines, direct labeling, color restraint). Keep the charts Colin already likes but declutter them, and add a focused set of higher-insight visualizations (calendar heatmap, sparkline leaderboard, cumulative season chart, run-type small multiples, first-vs-second-half slopegraph). Replace manual CSV exports with a GitHub Action that pulls the published Google Sheet every Sunday and auto-deploys via Vercel. A baseline reference doc + screenshots are captured first so the current look is recoverable.

---

## Problem Frame

The dashboard was built end-of-2024 for the 2025 season and hardcodes that year everywhere: a fixed 30-member list, fixed header-row indices (totals on rows 8-9, header on row 10), and `new Date(2025, ...)` in the parser. The 2026 sheet has drifted — 33 members (Alex B, Dan B, Deano added), header pushed to row 11, and summary rows split into cumulative / 2025 / 2026 bands — so it will not parse as-is. Colin also updates the source Google Sheet weekly and currently hand-exports a CSV and redeploys.

On visuals: the current dashboard's warm theme (coffee/cream/pink/terracotta, grain textures, gradient nav pills) feels busy, and the charts carry chartjunk (dashed gridlines, boxed legends, decorative accent bars, per-element animations). The richest signal in the data — attendance cadence, streaks, seasonality, who's climbing or fading, cumulative season progress — is under-exploited. Colin wants the clean reference aesthetic AND Tufte-grade information density: keep the graphs he likes, declutter them, and surface more honest, high-density insight.

---

## Requirements

- R1. The current dashboard's appearance and behavior are documented (reference doc + screenshots) before any redesign, so the prior state is recoverable.
- R2. A single parser correctly ingests both the 2025 and 2026 CSV schemas without per-year hardcoding of member lists or header-row positions.
- R3. Both 2025 and 2026 live on the same deployed site, switchable via a year control; each year shows only its own data.
- R4. The 2025 "Wrapped" experience continues to work unchanged (it consumes 2025 data and keeps its existing visuals).
- R5. The dashboard is restyled toward the clean reference aesthetic (light surfaces, subtle borders, rounded cards, refined type, restrained motion).
- R6. The current season's data is pulled automatically from the published Google Sheet every Sunday and deployed without a manual export step.
- R7. The final planning document is copied into a Solo scratchpad.
- R8. Dashboard visualizations follow Tufte principles — existing charts are retained but decluttered (chartjunk removed, direct labeling, color restraint), and a focused set of higher-insight, high-density visualizations is added that surface trends the current dashboard misses.

---

## Scope Boundaries

- No 2026 "Wrapped" experience this round — Wrapped stays a year-end retrospective; 2026 is mid-season.
- No restyle of the existing 2025 Wrapped slides — they keep their current look (R4).
- No combined / all-time merged view — the year switcher shows one year at a time; no cross-year member-name reconciliation.
- No move away from the static-SPA model — no backend, no runtime data fetching beyond the existing client-side CSV load.
- The source Google Sheet's own structure/formulas are not modified; the plan only consumes its published output.
- No heavyweight charting framework swap (e.g. Nivo/D3-everything). Keep Recharts for what it does well; add only one small maintained dependency (calendar heatmap) and lightweight custom SVG for the rest.

### Deferred to Follow-Up Work

- Repo rename `cpdis/fctc2025` → a year-neutral name (e.g. `fctc-dashboard`): optional, separate chore; the current remote keeps working regardless.
- 2026 Wrapped build-out: revisit near end of 2026 season.
- Stretch visualizations (bump chart of leaderboard rank-over-time, horizon chart of guest anomalies): build only if the core set lands cleanly with budget to spare (see U7).

---

## Context & Research

### Current chart inventory

- `src/components/Dashboard/StatsCards.jsx` — KPI cards (total runs, total km, active members, avg attendance).
- `src/components/Dashboard/AttendanceChart.jsx` — multi-line "attendance by run type over time." Carries the most chartjunk: dashed `CartesianGrid`, boxed custom legend, a decorative gradient accent bar, and ~130 lines of brittle segment-splitting logic to handle gaps. Prime declutter + simplify target.
- `src/components/Dashboard/Leaderboard.jsx` — attendance + distance leaderboards (ranked lists).
- `src/components/Dashboard/RunTypeBreakdown.jsx` — run-type distribution.
- `src/components/Dashboard/RunsTable.jsx` — full runs table.
- `src/components/Dashboard/DistanceChart.jsx` — **dead code**: defined but imported nowhere. Delete during the restyle.

### Data surface available for new visualizations

Per run: date, meet (location), run type, approx km, actual km, per-member attendance (boolean), +1 guests, total attendance. Per member (computed): total runs, total km, attended-run list. `calculations.js` already derives streaks, day preference, peak month, co-runners, regulars, monthly averages (currently Wrapped-only). This is enough to build, with new derivations:

- Cumulative club km / attendance over the season (season-progress line).
- Per-member monthly attendance series (sparklines).
- Per-run-type monthly counts (small multiples → seasonality).
- First-half vs second-half attendance per member (slopegraph → who's ramping / fading — especially meaningful mid-2026).
- Run frequency by calendar date (GitHub-style heatmap → cadence, gaps, streaks).
- Member rank-over-month (bump chart — stretch).

### Tufte principles → actionable rules (applied in U5/U6/U7)

- **Data-ink ratio** (VDQI ch.4): every pixel earns its keep. Recharts defaults: `axisLine={false}`, `tickLine={false}`, drop `CartesianGrid` or a single dotted line ≤20% opacity. No decorative accent bars on cards.
- **Chartjunk removal** (VDQI ch.5): no 3D, no gradient fills unless encoding a variable, no decorative card-top gradients/grain.
- **Small multiples** (Envisioning Information ch.2): same scale + layout repeated across a dimension — one mini-chart per run type / per member, directly comparable.
- **Sparklines** (Beautiful Evidence ch.2): tiny axis-free "data-words" embedded in table rows; number and trend live together.
- **Direct labeling** (VDQI ch.4): label line endpoints / data points in place; kill boxed legends.
- **Layering & separation** (Envisioning Information ch.3): separate by luminance, not hue — foreground data saturated, reference context low-saturation grey.
- **Color restraint**: one accent hue for the highest-signal datum; grey for context; ≤4-5 categorical hues, otherwise encode by position/shape.

### External References

- Calendar heatmap library: `react-activity-calendar` (grubersjoe) — actively maintained (2026 releases), SSR-safe, light/dark, configurable levels. Preferred over stale `react-calendar-heatmap`. Health-check before adding (recent releases, adoption) per deps policy.
- Sparklines / slopegraph / dot plot: roll custom SVG (`<polyline>` / `<line>`), ~40-80 lines each. `react-sparklines` is unmaintained (avoid). Recharts mini-`LineChart` with axes off is an alternative for sparklines.
- Bump chart (stretch): Nivo `<Bump>` exists but pulls a heavy D3 peer dep for one view — prefer ~80 lines of custom SVG if built at all.
- Google Sheets published CSV endpoint: `https://docs.google.com/spreadsheets/d/<ID>/export?format=csv&gid=<GID>` (link-viewable sheets) or Publish-to-web `…/pub?gid=<GID>&single=true&output=csv`. Exact form verified at execution.
- GitHub Actions scheduled workflows: `on: schedule: - cron:` (UTC), `permissions: contents: write`, commit-if-changed. Caveats: scheduled runs can be delayed under load and auto-disable after 60 days of repo inactivity. Vercel deploys on push.

### Schema comparison (2025 vs 2026 CSV)

| Aspect | 2025 | 2026 |
|---|---|---|
| Header row (0-indexed) | line 9 (`Date,Meet,Run,Approx kms,Actual kms,…`) | line 10 |
| Summary rows above header | rows 7-8 (km totals, attendance totals) | rows 6-9 (cumulative km, cumulative attendance, 2025 band, 2026 band) |
| Member count | 30 | 33 (adds Alex B, Dan B, Deano) |
| Trailing columns | `+1's`, `Total Attendance per run`, `Aggregate Kilometers Per Run` (headered) | `+1's` then unheadered trailing values |
| Fixed leading columns | `Date, Meet, Run, Approx kms, Actual kms` (identical) | identical |

Implication: header position and summary-row layout are unstable across years, but the **header row is self-describing** (starts with `Date`; members sit between `Actual kms` and `+1's`). Robust strategy: locate the header row by content, derive members from it, compute all totals from the data rows.

---

## Key Technical Decisions

- **Self-describing parse over positional parse:** Locate the header row by matching the leading `Date,Meet,Run` signature; derive member columns as everything between `Actual kms` and `+1's`. Eliminates per-year header-index and member-list hardcoding (R2) and absorbs future roster changes.
- **Compute totals from run data, not summary rows:** Member km = Σ attended-run actual km; member attendance = count of attended runs; club totals aggregate those. Layout-independent across both years. Verified against the sheet's displayed totals.
- **Year as explicit input, registered in a small config:** `{ 2025: '/data/2025.csv', 2026: '/data/2026.csv' }`; parser takes the year so dates stop being hardcoded. New years = drop a file + one config line.
- **Stable parser output contract:** Preserve the existing output shape so `calculations.js`, Wrapped, and dashboard components keep working without rewrites (R4).
- **Year selection in URL + state, default to latest** (2026). Per-year only — no merge logic.
- **Published-CSV + GitHub Action sync:** Sunday cron fetches the current season's published CSV, writes `public/data/<year>.csv`, commits only on change; Vercel auto-deploys. 2025 is frozen (committed once); only the current season's tab is fetched weekly.
- **Design tokens layered into `theme.js` + Tailwind, not a framework swap:** Clean light tokens added alongside the existing palette so Wrapped's warm theme survives; dashboard migrates, Wrapped keeps the old tokens.
- **Tufte data-viz philosophy as a shared chart foundation:** Centralize chart defaults (axes off, no gridlines/minimal, direct labels, one accent hue + greys) as reusable config/primitives so every dashboard chart is consistent and decluttered. Existing charts are retained but stripped of chartjunk; new charts are built to the same bar (R8).
- **Separate metrics derivation from rendering:** New dashboard trends live in a dedicated `src/utils/dashboardMetrics.js` (unit-tested), not bloating `calculations.js` (kept Wrapped-focused). Keeps files under the ~500 LOC guideline and makes the data honest/testable independent of the charts.
- **Minimal new dependencies:** one maintained lib (`react-activity-calendar`) for the calendar heatmap; everything else (sparklines, slopegraph, dot plots) is lightweight custom SVG. Avoid heavy D3/Nivo for single-view charts.

---

## Open Questions

### Resolved During Planning

- Sync mechanism? → GitHub Action + published CSV (user-selected).
- Redesign scope / 2026 Wrapped? → Dashboard only; keep 2025 Wrapped; no 2026 Wrapped (user-selected).
- Year navigation model? → Year switcher, per-year views, no all-time merge (user-selected).
- Keep or replace existing graphs? → Keep the ones Colin likes; declutter to Tufte standard rather than discard (user direction).
- How to survive roster/header drift? → Self-describing header detection + computed totals.

### Deferred to Implementation

- **Exact published-CSV URL form and the 2026 tab's `gid`:** depends on the sheet's current sharing setting and tab layout; identified when wiring U8.
- **Whether the live sheet holds both years as separate tabs or only the current season:** confirmed at execution.
- **Final font pairing for the clean aesthetic:** Bricolage Grotesque may stay or be swapped; decided visually in U5 against the reference.
- **Cron time in UTC:** Sunday-evening AEST/AEDT slot; finalized in U8.
- **Which stretch visualizations (if any) ship:** decided after the core viz set lands (U7).
- **Mobile density strategy for high-information charts:** small multiples and sparkline tables need a mobile fallback (fewer columns / horizontal scroll / collapse); finalized during U7 against real screenshots.
- **Computed-totals vs sheet-displayed-totals discrepancies:** reconcile during U2.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

Parser data flow (layout-independent):

```
raw CSV text ──► split into rows
                   │
                   ▼
         find header row  ──►  row whose col0 == "Date" and contains "Run","Actual kms"
                   │
                   ▼
        derive columns:
          fixed   = [Date, Meet, Run, Approx kms, Actual kms]   (cols 0–4)
          members = header cols after "Actual kms" up to "+1's"  (dynamic length)
                   │
                   ▼
        for each data row below header:
          parse date with the dataset's YEAR (config), attendance per member,
          actual km, +1's, attendees[]
                   │
                   ▼
        COMPUTE (do not read summary rows):
          memberTotals, club totals, runsByType/Location/Month, leaderboards
                   │
                   ▼
        return SAME output shape as today  ──►  Dashboard + calculations.js + Wrapped
```

Data → visualization map (R8):

```
parser output ──► dashboardMetrics.js derivations ──► chart components
  ├─ cumulative km/attendance series      ──► Season-progress line (core)
  ├─ run frequency by date                ──► Calendar heatmap (core)
  ├─ per-member monthly attendance series ──► Sparkline leaderboard table (core)
  ├─ per-run-type monthly counts          ──► Run-type small multiples (core/stretch)
  ├─ first-half vs second-half per member ──► Slopegraph: ramping vs fading (core)
  └─ member rank by month                 ──► Bump chart (stretch)

shared Tufte chart config/primitives (axes off, direct labels, 1 accent + greys,
SVG sparkline/slopegraph/dotplot) ──► consumed by BOTH retained + new charts
```

---

## Implementation Units

### U1. Capture current-state baseline (reference doc + screenshots)

**Goal:** Freeze a recoverable record of the dashboard's current look and behavior before redesign.

**Requirements:** R1

**Dependencies:** None — must run before redesign units (U5–U7) touch visuals.

**Files:**
- Create: `docs/reference/2025-dashboard-baseline.md` (routes, component tree, theme, data flow, current chart inventory, known quirks)
- Create: `docs/reference/screenshots/` (fresh captures: dashboard top, leaderboard/run-type row, attendance chart, runs table, run detail, Wrapped intro/selector/numbers — desktop + mobile)
- Reference: existing `.playwright-mcp/dashboard-current.png`, `public/screenshots/*`

**Approach:**
- Run the app locally (`npm run dev`), capture each major view at desktop + mobile breakpoints.
- Write the reference doc describing structure and current quirks (hardcoded year/members, chartjunk, dead `DistanceChart`).

**Test scenarios:** Test expectation: none — documentation/screenshot capture.

**Verification:** Reference doc renders, links all screenshots, covers every route in `App.jsx`; both breakpoints captured.

---

### U2. Schema-tolerant data parser

**Goal:** Rewrite `dataParser.js` to ingest both years via self-describing header detection and computed totals, with year as an explicit argument.

**Requirements:** R2, R4

**Dependencies:** None (parallel with U1).

**Files:**
- Modify: `src/utils/dataParser.js`
- Create: `src/utils/dataParser.test.js`
- Test fixtures: copy trimmed fixtures from `planning/reference/*.csv` into a test fixtures dir

**Approach:**
- Locate header row by content; derive member columns dynamically between `Actual kms` and `+1's`; preserve emoji names (`Alex 👑`).
- Accept `year`; use it in `new Date(year, …)`. Keep export `parseRunData(csvText, year)`.
- Compute `memberTotals`, club totals, `runsByType/Location/Month`, leaderboards from parsed rows (drop summary-row reliance).
- Preserve the existing return shape exactly (R4). Drop hardcoded `MEMBER_COLUMNS`; switch any consumer to `data.members`.

**Execution note:** Fixture tests for both years first, to lock the output contract before deleting positional logic.

**Patterns to follow:** `AttendanceChart.jsx:93` year-from-data derivation; keep `normalizeRunType`.

**Test scenarios:**
- Happy path: 2025 fixture → 30 members; run count + a spot-checked member's totalKm/totalRuns match sheet totals within rounding.
- Happy path: 2026 fixture → 33 members incl. Alex B, Dan B, Deano; `Alex 👑` preserved.
- Edge: header not at a fixed index → still found (extra leading rows).
- Edge: future/empty rows (no attendance, no km) → skipped.
- Edge: mixed markers (`x`, emoji, `-`, blank) → only genuine attendance counts.
- Edge: `year` flows into dates → `Fri, 2-Jan` parses to correct year.
- Integration: output feeds `calculations.js` and Wrapped stats compute for 2025 (guards R4).

**Verification:** Both fixtures parse; computed totals reconcile with sheet totals (note deltas); 2025 Wrapped renders identical stats.

---

### U3. Multi-year data layer + year selection

**Goal:** Load the correct per-year CSV by selected year, default to latest, expose selection to the UI.

**Requirements:** R3, R4

**Dependencies:** U2.

**Files:**
- Modify: `src/App.jsx`
- Create: `src/config/years.js` (`{ 2025: '/data/2025.csv', 2026: '/data/2026.csv' }`, `LATEST_YEAR`)
- Rename: `public/data/runs.csv` → `public/data/2025.csv`
- Create: `public/data/2026.csv` (from the 2026 export, trimmed to live shape)
- Test: `src/App.test.jsx` (or a thin data-layer test)

**Approach:**
- `selectedYear` state in `App`, default `LATEST_YEAR`, reflected in URL (query param/route segment) for shareable views.
- Fetch `YEARS[selectedYear]`, `parseRunData(csv, selectedYear)`; re-fetch on change.
- 2025 Wrapped routes always load `2025.csv` regardless of switcher (R4).
- Keep loading/error states per year load.

**Patterns to follow:** existing `useEffect` fetch in `App.jsx`.

**Test scenarios:**
- Happy: default → latest year (2026) renders.
- Happy: switching year → corresponding CSV fetched/parsed, dashboard updates.
- Edge: missing/404 CSV → error state, no crash.
- Integration: `/2025wrapped` loads 2025 data even when dashboard year is 2026.

**Verification:** Both years render via switcher; Wrapped unaffected by switcher state.

---

### U4. Dashboard metrics & trends derivation

**Goal:** Derive the new trend datasets (cumulative series, member monthly series, run-type monthly counts, first/second-half splits, calendar frequency, rank-over-month) that power the Tufte visualizations — separate from rendering and unit-tested.

**Requirements:** R8

**Dependencies:** U2 (parser output shape).

**Files:**
- Create: `src/utils/dashboardMetrics.js`
- Create: `src/utils/dashboardMetrics.test.js`

**Approach:**
- Pure functions over parser output: `cumulativeSeries(runs)`, `memberMonthlyAttendance(data)`, `runTypeMonthlyCounts(data)`, `firstVsSecondHalf(data)`, `runFrequencyByDate(runs)`, `rankByMonth(data)` (stretch).
- Reuse existing logic in `calculations.js` where applicable (streaks, monthly) without coupling Wrapped to the dashboard.
- Keep honest: handle partial seasons (2026 mid-year), zero-attendance members, and missing dates without fabricating points.

**Patterns to follow:** existing reducers in `dataParser.js` (`runsByMonth`, etc.) and `calculations.js`.

**Test scenarios:**
- Happy: cumulative series is monotonic non-decreasing and ends at club totals.
- Happy: member monthly series sums to each member's total runs.
- Edge: a month with no runs → present as 0, not skipped (calendar/small-multiple integrity).
- Edge: partial 2026 season → first/second-half split uses the season midpoint, not a hardcoded month.
- Edge: member with zero attendance → excluded from sparkline rows, not a divide-by-zero.

**Verification:** All derivations unit-tested against both fixtures; totals reconcile with parser output.

---

### U5. Clean + Tufte design-system foundation

**Goal:** Establish the new minimal aesthetic AND the shared Tufte chart foundation as reusable tokens + config + SVG primitives, without disturbing Wrapped's warm theme.

**Requirements:** R5, R8, R4

**Dependencies:** None for tokens (parallel with U2–U4); lands before U6/U7 consume it.

**Files:**
- Modify: `src/utils/theme.js` (add clean light tokens + a restrained data-color scale alongside the existing palette; don't remove Wrapped colors/variants)
- Modify: `src/index.css` (base surface/type rules, Tailwind 4 theme vars)
- Modify: `index.html` (font pairing if changed)
- Create: `src/utils/chartConfig.js` (shared Recharts defaults: axes off/minimal, no gridline or ≤20% dotted, tooltip style, one accent + greys)
- Create: `src/components/Dashboard/viz/Sparkline.jsx`, `Slopegraph.jsx`, `DotPlot.jsx` (lightweight custom-SVG primitives)
- Reference: `planning/reference/FF17D9DE-DFB7-423C-BFE6-8D377FD6486B.jpeg`

**Approach:**
- Tokens from the reference: near-white app bg, white cards, hairline grey borders, generous radius, soft low shadows, refined headline + clean sans body, a single dark accent for active controls.
- Data-color scale built for layering: saturated foreground, low-saturation grey context; ≤5 categorical hues.
- `chartConfig.js` centralizes the Tufte defaults so retained and new charts share one look.
- SVG primitives are dependency-free, accessible (title/aria), and responsive.
- Namespace tokens so Wrapped keeps `cream/navy/pink/etc.`; one restrained dashboard motion baseline (replace busy framer variants on dashboard only).

**Test scenarios:**
- Happy: Sparkline/Slopegraph/DotPlot render expected SVG geometry for a known input (smoke/render tests).
- Edge: single-point / empty series → primitive renders without throwing.

**Verification:** New tokens + chartConfig + primitives available; Wrapped renders unchanged.

---

### U6. Dashboard restyle + declutter existing charts + year switcher

**Goal:** Apply the clean system to the shell, header (with year switcher), and existing dashboard components; strip chartjunk from the charts Colin keeps.

**Requirements:** R5, R8, R3

**Dependencies:** U3 (year state), U5 (tokens + chartConfig).

**Files:**
- Modify: `src/components/Layout/Header.jsx` (remove grain SVG + gradient pills; clean nav; add year switcher reading/writing U3 state; de-year strings)
- Modify: `src/pages/Dashboard.jsx` (new surfaces, spacing, footer; one restrained reveal)
- Modify: `src/components/Dashboard/StatsCards.jsx`, `FilterBar.jsx`, `Leaderboard.jsx`, `RunTypeBreakdown.jsx`, `RunsTable.jsx`
- Modify: `src/components/Dashboard/AttendanceChart.jsx` (adopt `chartConfig`: drop dashed grid, boxed legend, decorative accent bar; direct-label run types at line ends; simplify the segment logic where possible)
- Delete: `src/components/Dashboard/DistanceChart.jsx` (dead code)
- Modify: `src/pages/RunDetail.jsx` (consistent shell)

**Approach:**
- White-surface cards, hairline borders, soft shadow, generous radius; tightened type scale; color reduced to data accents on neutral ground.
- Year switcher = clean segmented control / pill (active = the single dark accent, echoing the reference's dark "Continue" pill).
- Recharts via `chartConfig`: axes off/minimal, direct labels, restrained palette, lighter axes.
- Replace per-element entrance animations with one cohesive staggered reveal.
- Verify against the reference at desktop + mobile; check iOS safe areas (prior mobile/Wrapped viewport work exists).

**Test scenarios:**
- Happy: year switcher toggles 2025/2026; active state reflects current year.
- Edge: mobile width → header + switcher + cards usable (no overflow, adequate tap targets).
- Integration: switching year re-renders charts/tables/leaderboard with that year's data (ties to U3).

**Verification:** Side-by-side vs reference shows the cleaner aesthetic across all views + both breakpoints; existing charts decluttered; switcher works; Wrapped link still reaches the unchanged 2025 Wrapped.

---

### U7. New Tufte visualizations

**Goal:** Add a focused set of higher-insight, high-density visualizations built on `dashboardMetrics` + the U5 primitives/config.

**Requirements:** R8

**Dependencies:** U4 (metrics), U5 (primitives + chartConfig), U6 (restyled shell to slot into).

**Files:**
- Create: `src/components/Dashboard/viz/SeasonProgress.jsx` (cumulative km/attendance line — core)
- Create: `src/components/Dashboard/viz/CalendarHeatmap.jsx` (run frequency by date via `react-activity-calendar` — core)
- Create: `src/components/Dashboard/viz/SparklineLeaderboard.jsx` (member table: name, runs, km, 12-month attendance sparkline, current streak — core)
- Create: `src/components/Dashboard/viz/RunTypeSmallMultiples.jsx` (per-type monthly mini-charts → seasonality — core/stretch)
- Create: `src/components/Dashboard/viz/HalfSeasonSlopegraph.jsx` (first-vs-second-half attendance per member → ramping/fading — core)
- Modify: `src/pages/Dashboard.jsx` (compose the new sections)
- Modify: `package.json` (add `react-activity-calendar` after health-check)
- Tests: render/smoke tests per component with fixture-derived data

**Approach:**
- **Core set first:** SeasonProgress, CalendarHeatmap, SparklineLeaderboard, HalfSeasonSlopegraph. Add RunTypeSmallMultiples if it lands cleanly.
- Direct labeling + one accent hue throughout; sparkline table = the Tufte showpiece (number + trend together).
- Slopegraph is especially apt mid-2026 (who's showing up more/less than early season).
- Mobile: define a fallback for dense views (fewer columns / horizontal scroll / collapse) — verified on real screenshots.
- **Stretch (deferred unless budget):** bump chart (rank-over-month), horizon chart (guest anomalies) — custom SVG only.

**Patterns to follow:** U5 `chartConfig.js` + viz primitives; existing card layout in `Dashboard.jsx`.

**Test scenarios:**
- Happy: each component renders for a normal year (2025) with expected element counts (e.g., one sparkline row per active member).
- Edge: partial season (2026) → SeasonProgress stops at the latest run; slopegraph splits at season midpoint.
- Edge: empty/short series → component renders an empty/low state, not a crash.
- Integration: switching year re-renders all new viz with that year's metrics (ties to U3/U4).
- Accessibility: charts expose title/aria text for the key figure.

**Verification:** Core viz render correctly for both years at both breakpoints; new dependency health-checked; screenshots show high-density, decluttered, honest charts that read cleanly on mobile.

---

### U8. Automated weekly Sunday Google Sheets sync

**Goal:** A scheduled GitHub Action pulls the current season's published CSV every Sunday, commits on change, and triggers a Vercel deploy — no manual export.

**Requirements:** R6

**Dependencies:** U2 (committed CSV must parse), U3 (per-year file naming + config).

**Files:**
- Create: `.github/workflows/weekly-data-sync.yml`
- Create (optional): `scripts/fetch-sheet.sh` or inline `curl`
- Modify (docs): `README.md` sync section (U9)

**Approach:**
- `on: schedule: - cron:` Sunday slot (UTC, AEST/AEDT evening) + `workflow_dispatch`.
- `permissions: contents: write`; fetch the current season's published CSV `gid`, write `public/data/<currentYear>.csv`, `git diff --quiet || commit & push`.
- Vercel deploys on push. 2025.csv frozen (not pulled). Identify exact URL + 2026 `gid` against the live sheet at wiring time.

**Test scenarios:**
- Happy: manual `workflow_dispatch` fetches, writes the CSV, commits only on change.
- Edge: no change → no commit, no empty deploy.
- Edge: fetch fails (unshared / network) → workflow fails loudly, no truncated/empty commit.
- Integration: committed CSV is parsed by U2 on next build (no schema break).

**Verification:** Manual dispatch produces a parseable `public/data/2026.csv`; scheduled trigger registered; a forced content change yields commit + deploy.

---

### U9. Metadata, copy, and docs cleanup

**Goal:** De-year the site chrome, document the new data/sync/viz model, refresh the README.

**Requirements:** R5, R6, R8

**Dependencies:** U6/U7 (final UI), U8 (sync behavior).

**Files:**
- Modify: `index.html` (`<title>` → year-neutral, e.g. "FCTC | Filament Coffee Track Club")
- Modify: `src/pages/Dashboard.jsx` footer (season label derives from selected year)
- Modify/Create: `README.md` (overview, local run/build, data model + per-year files, parser behavior, the new metrics/viz layer, GitHub Action sync, how to add a future year)

**Approach:** Footer/season label derives from selected year. README documents data files, `years.js`, parser self-describing behavior, `dashboardMetrics` + viz components, the sync (cron, how to change URL/gid), and the one-line process to onboard a future year.

**Test scenarios:** Test expectation: none — copy/docs; footer-derives-year covered by U6's switcher scenario.

**Verification:** No 2025-only hardcoded chrome on the dashboard; README accurately describes data + sync + viz.

---

## System-Wide Impact

- **Interaction graph:** Parser output feeds `Dashboard.jsx`, all `components/Dashboard/*`, `dashboardMetrics.js`, `calculations.js`, and the Wrapped tree. Stable output contract (U2) prevents ripples into Wrapped (R4).
- **Error propagation:** Per-year fetch failures surface in App's error state (U3); the sync Action fails loudly in CI (U8); viz components render empty states, not crashes, on short/empty series (U7).
- **State lifecycle risks:** Year switch fully replaces `data` (no stale merge); Wrapped ignores the dashboard's selected year and always loads 2025.
- **API surface parity:** `parseRunData` gains a `year` arg — update all callers.
- **Integration coverage:** parser → metrics/calculations → charts/Wrapped; year-switch → re-render.
- **Unchanged invariants:** Parser return shape, `normalizeRunType`, Wrapped visuals/theme, route paths — all preserved.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Computed totals diverge from sheet totals (COUNTUNIQUE, +1's quirks) | Spot-check both years in U2; run `/data-check`; document intentional deltas |
| Parser rewrite silently breaks 2025 Wrapped | Fixture tests lock output contract before deleting positional logic (U2); Wrapped integration scenario |
| Tufte/redesign scope creep (too many new charts) | Core-vs-stretch split in U7; metrics (U4) decoupled so viz can land incrementally; stretch viz deferred by default |
| High-density viz unreadable on mobile | Explicit mobile fallback in U7; verify on real screenshots; `/polish` pass |
| New dependency (`react-activity-calendar`) unmaintained/heavy | Health-check before adding (recent releases/adoption); everything else is custom SVG; one dep only |
| Dishonest charts (fabricated points, misleading partial-season trends) | U4 derivations handle partial 2026 + zero-cases explicitly and are unit-tested; slopegraph splits at true season midpoint |
| GitHub scheduled workflow delayed / auto-disabled after 60 days | `workflow_dispatch` fallback; repo gets regular commits via the sync; note in README |
| Published-CSV makes data publicly fetchable | User accepted; Sheets API + service-account is the privacy upgrade path |
| Wrong `gid`/URL pulls wrong tab | Verify against live sheet in U8; manual dispatch validates before schedule |
| Redesign drifts into generic "AI slop" | Iterate against the reference + Tufte rules with screenshots (U6/U7); restrained palette + one motion moment |

---

## Phased Delivery

### Phase 1 — Foundations (no visual change yet)
- U1 baseline, U2 parser, U3 multi-year data layer, U4 metrics derivation. Ship-able: both years load and parse; metrics tested.

### Phase 2 — Redesign + decluttered existing charts
- U5 design system + Tufte foundation, U6 restyle + declutter + year switcher. Ship-able: clean dashboard, both years, existing charts to Tufte standard.

### Phase 3 — New insight visualizations + automation + docs
- U7 new viz (core, then stretch), U8 weekly sync, U9 docs. Ship-able: high-insight dashboard, hands-off weekly updates, documented.

---

## Alternative Approaches Considered

- **Discard existing charts and rebuild from scratch:** Rejected — Colin likes the current graphs; decluttering to Tufte standard preserves familiarity and is less work.
- **Adopt Nivo/D3 for all charts:** Rejected — heavy dep for a hobby static site; Recharts + one small lib + custom SVG covers the need with less weight.
- **Google Sheets API + service account (private sheet):** Rejected for now — user chose published CSV; keep as the privacy upgrade path.
- **Vercel Cron + serverless runtime fetch:** Rejected — abandons the pure-static model for no gain.
- **Single merged multi-year / all-time view:** Rejected — roster + name reconciliation complexity the user doesn't want.
- **Keep positional parser, branch on year:** Rejected — re-breaks whenever summary rows shift; self-describing parse is the first-principles fix.

---

## Documentation / Operational Notes

- README (U9) is the operational runbook: sync cron, how to change source URL/gid, how to add a future year (drop `public/data/<year>.csv` + one line in `years.js`), and a short map of `dashboardMetrics` → viz components.
- After first deploy, confirm Vercel Bot Protection + AI Bot blocking remain enabled (deployment defaults; prior bot-traffic incident).
- The final plan is copied to a Solo scratchpad (R7) as part of handoff.

---

## Sources & References

- Related code: `src/utils/dataParser.js`, `src/utils/calculations.js`, `src/App.jsx`, `src/utils/theme.js`, `src/components/Layout/Header.jsx`, `src/components/Dashboard/AttendanceChart.jsx`
- Data fixtures: `planning/reference/FCTC - Run_ Attendance Schedule (2025) - Sheet1.csv`, `planning/reference/250101 FCTC - Run_ Attendance Schedule - 2026.csv`
- Design reference: `planning/reference/FF17D9DE-DFB7-423C-BFE6-8D377FD6486B.jpeg`
- Viz/Tufte research: VDQI, Envisioning Information, Beautiful Evidence; `react-activity-calendar` (grubersjoe); Tufte slopegraphs (Charlie Park)
- Source Google Sheet: https://docs.google.com/spreadsheets/d/1YEKXqp6A4LoGUyg7Rsm3w3MUkbfgRNIAWQkGBYulO2o/edit
- Deploy target: Vercel; repo `cpdis/fctc2025`
