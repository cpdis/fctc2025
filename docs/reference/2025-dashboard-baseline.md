# FCTC Dashboard — 2025 Baseline (pre-redesign snapshot)

Captured 2026-05-28, documenting the dashboard **as it existed before** the 2026 multi-year + Tufte redesign
(plan: `docs/plans/2026-05-28-001-feat-fctc-dashboard-2026-redesign-plan.md`). This exists so the prior
state is recoverable / comparable. Screenshots are in `docs/reference/screenshots/` (current-state captures;
the code was visually unchanged from December 2025 through this snapshot).

## Screenshots

| File | View |
|------|------|
| `screenshots/01-dashboard-full.png` | Full dashboard (desktop) |
| `screenshots/02-dashboard-typography.png` | Dashboard typography pass |
| `screenshots/03-wrapped-selector.png` | Wrapped member selector |
| `screenshots/04-wrapped-intro.png` | Wrapped intro slide |
| `screenshots/05-wrapped-numbers.png` | Wrapped big-numbers slide |
| `screenshots/06-mobile-a.jpeg`, `07-mobile-b.jpeg` | Mobile views |

## Stack

React 19, Vite 7, Tailwind CSS v4 (CSS-first `@theme` in `src/index.css`), Recharts 3, Framer Motion 12,
React Router 7, PapaParse 5. Static SPA deployed on Vercel (repo `cpdis/fctc2025`), SPA rewrites in
`vercel.json`. Single client-side data fetch, no backend.

## Routes (`src/App.jsx`)

- `/` and `/dashboard` → `Dashboard`
- `/run/:runId` → `RunDetail`
- `/wrapped`, `/wrapped/:member` → `Wrapped`
- `/2025wrapped`, `/2025wrapped/:member` → `Wrapped`

`App` fetches a single hardcoded `/data/runs.csv`, parses it once with `parseRunData`, holds `{data, loading, error}`
in state, and passes `data` to every route. Loading + error states render inline.

## Component tree

```
App (data fetch + routing)
├── Dashboard (src/pages/Dashboard.jsx)
│   ├── Header (src/components/Layout/Header.jsx)        nav: Dashboard | 2025 Wrapped; navy bar, grain SVG, gradient pills
│   ├── StatsCards         KPIs: total runs, total km, active members, avg attendance
│   ├── FilterBar          filters: run type, month, location
│   ├── Leaderboard        attendance + distance ranked lists
│   ├── RunTypeBreakdown   run-type distribution
│   ├── AttendanceChart    multi-line attendance by run type over time (Recharts)
│   └── RunsTable          all runs
├── RunDetail (src/pages/RunDetail.jsx)
└── Wrapped (src/pages/Wrapped.jsx)
    ├── MemberSelector
    └── WrappedContainer → slides/ (Intro, BigNumbers, Streak, Distance, PeakMonth,
        Regulars, DayPreference, TopAttendee, FavoriteRun, SpecialMoments, Outro)
```

## Data flow

`public/data/runs.csv` (the 2025 Google Sheet export) → `parseRunData(csvText)` in `src/utils/dataParser.js`
→ a normalized object consumed by the dashboard components and by `src/utils/calculations.js`
(`calculateMemberStats`, `calculateClubStats`, `getMemberTitle`) which powers Wrapped.

Parser output shape (the contract the redesign must preserve):
`{ runs[], members[], memberTotals{}, leaderboard[], distanceLeaderboard[], totalRuns, totalClubKm,
totalAttendanceInstances, runsByType{}, runsByLocation{}, runsByMonth{}, avgAttendance }`.

## Theme / palette (`src/utils/theme.js` + `src/index.css`)

Warm "coffee" identity: pink `#fa688e`, mint `#9ed1af`, orange `#ff511b`, cream `#f2eee2`, navy `#020912`,
amber accents, plus legacy aliases (coffee/latte/terracotta/espresso/roast/mocha). Fonts: Bricolage Grotesque
(display) + DM Sans (body), loaded in `index.html`. `body` background is cream. Heavy decorative layer:
grain-texture overlays, organic border-radii, warm shadows, gradient backgrounds, many Framer Motion variants
(bounceIn, squashStretch, tiltHover, wiggle, pulseGlow, etc.).

## Chart inventory

- `StatsCards.jsx` — KPI cards.
- `AttendanceChart.jsx` — multi-line "attendance by run type over time." Carries the most chartjunk:
  dashed `CartesianGrid`, a boxed custom legend, a decorative gradient accent bar, and ~130 lines of brittle
  segment-splitting logic to break lines across >1-month gaps.
- `Leaderboard.jsx` — attendance + distance ranked lists.
- `RunTypeBreakdown.jsx` — run-type distribution.
- `RunsTable.jsx` — full runs table.
- `DistanceChart.jsx` — **dead code**: defined but imported nowhere. (Scheduled for deletion in the redesign.)

## Known quirks / debt (motivating the redesign)

- **Hardcoded 2025 everywhere:** `dataParser.js` uses `new Date(2025, …)` and a fixed 30-name `MEMBER_COLUMNS`;
  header/summary rows are read by fixed line index. The 2026 sheet (33 members, shifted header rows) will not
  parse as-is.
- **Member totals read from spreadsheet summary rows** rather than computed from the data — fragile across the
  2025↔2026 layout differences.
- **Single data file:** `App.jsx` fetches one `/data/runs.csv`; no concept of multiple years.
- **Chartjunk + busy theme:** grain, gradients, per-element animations work against the cleaner direction.
- **Year strings hardcoded** in `Header.jsx` ("2025 Season", "2025 Wrapped"), `Dashboard.jsx` footer, `index.html` title,
  and several Wrapped slides.
- **`DistanceChart.jsx` is dead code.**

## How to run (current)

`npm install` → `npm run dev` (Vite). Build: `npm run build`. Data lives in `public/data/runs.csv`.
