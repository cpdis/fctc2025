import { Routes, Route, useSearchParams } from 'react-router-dom'
import { useState, useEffect, useMemo } from 'react'
import Dashboard from './pages/Dashboard'
import Wrapped from './pages/Wrapped'
import RunDetail from './pages/RunDetail'
import { parseRunData, combineYearData } from './utils/dataParser'
import { YEARS, YEAR_LIST, resolveYear, isAllTime } from './config/years'

// The 2025 Wrapped retrospective is pinned to 2025 forever, regardless of which
// year the dashboard is currently viewing. The Dashboard follows the selected
// year instead (see the ?year contract below).
const WRAPPED_YEAR = 2025

// Fetch one year's CSV and parse it. Rejects with a descriptive error on a
// non-OK HTTP response (fetch itself only rejects on network failures).
function loadYear(year) {
  return fetch(YEARS[year])
    .then((response) => {
      if (!response.ok) {
        throw new Error(`Failed to load ${year} data (HTTP ${response.status})`)
      }
      return response.text()
    })
    .then((csv) => parseRunData(csv, year))
}

/**
 * The season store: every season in YEARS, fetched once in parallel and
 * parsed, keyed by year (KTD5). All the CSVs together are about 26 KB, so one
 * up-front load beats a fetch per view: a year switch is instant, a run link
 * resolves in its own season whatever the view, and Wrapped reads 2025 from
 * the same store.
 *
 * @returns {{ seasons: Record<number, object>|null, error: string|null }}
 *   `seasons` stays null until every season has parsed; a failed fetch sets
 *   `error` instead.
 */
function useSeasons() {
  const [store, setStore] = useState({ seasons: null, error: null })

  useEffect(() => {
    let cancelled = false

    Promise.all(YEAR_LIST.map(loadYear))
      .then((parsed) => {
        if (cancelled) return
        const seasons = Object.fromEntries(YEAR_LIST.map((year, i) => [year, parsed[i]]))
        setStore({ seasons, error: null })
      })
      .catch((err) => {
        if (!cancelled) setStore({ seasons: null, error: err.message })
      })

    // StrictMode runs this effect twice in development; ignore the first run.
    return () => {
      cancelled = true
    }
  }, [])

  return store
}

function App() {
  // ?year contract: the selected dashboard view is driven entirely by the URL
  // query param `?year=YYYY` (or `?year=all`). The year controls write it
  // through yearSwitchParams (utils/dashboardPaths). Absent/invalid values
  // fall back to LATEST_YEAR.
  const [searchParams] = useSearchParams()
  const selectedYear = resolveYear(searchParams.get('year'))

  const { seasons, error } = useSeasons()

  // All time merges every season (newest first, as YEAR_LIST runs). Built once
  // per load, so switching to it and back never recomputes it.
  const allTime = useMemo(
    () => seasons && combineYearData(YEAR_LIST.map((year) => seasons[year])),
    [seasons]
  )

  // Both screens sit on the Poster paper (styles/poster.css), so the first
  // thing on screen already matches the saved theme.
  if (error) {
    return (
      <div className="poster status-page" role="alert">
        <h1 className="display">Error loading data</h1>
        <p className="mono soft">{error}</p>
      </div>
    )
  }

  if (!seasons) {
    return (
      <div className="poster status-page" role="status">
        <div className="stripe" aria-hidden="true" />
        <p className="mono soft">Loading run data...</p>
      </div>
    )
  }

  // The selected view: one season, or every season merged. A single season
  // is compared with the one before it (YEAR_LIST runs newest first); the
  // earliest season and All time have nothing to compare with.
  const view = isAllTime(selectedYear) ? allTime : seasons[selectedYear]
  const previous = isAllTime(selectedYear) ? null : (seasons[YEAR_LIST[YEAR_LIST.indexOf(selectedYear) + 1]] ?? null)
  const dashboard = <Dashboard data={view} previous={previous} allTime={allTime} />
  const runDetail = <RunDetail seasons={seasons} />
  const wrapped = <Wrapped data={seasons[WRAPPED_YEAR]} />

  return (
    <Routes>
      {/* The app's own domain serves the dashboard at the root; fctc.fun
          proxies it under /dashboard (KTD9), so both mount points route the
          same pages. */}
      <Route path="/" element={dashboard} />
      <Route path="/dashboard" element={dashboard} />
      <Route path="/run/:runId" element={runDetail} />
      <Route path="/dashboard/run/:runId" element={runDetail} />
      <Route path="/wrapped" element={wrapped} />
      <Route path="/wrapped/:member" element={wrapped} />
      <Route path="/2025wrapped" element={wrapped} />
      <Route path="/2025wrapped/:member" element={wrapped} />
    </Routes>
  )
}

export default App
