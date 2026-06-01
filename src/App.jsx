import { Routes, Route, useSearchParams } from 'react-router-dom'
import { useState, useEffect } from 'react'
import Dashboard from './pages/Dashboard'
import Wrapped from './pages/Wrapped'
import RunDetail from './pages/RunDetail'
import { parseRunData, combineYearData } from './utils/dataParser'
import { YEARS, YEAR_LIST, resolveYear, isAllTime } from './config/years'

// The 2025 Wrapped retrospective is pinned to 2025 forever, regardless of which
// year the dashboard is currently viewing. The Dashboard/RunDetail routes follow
// the selected year instead (see the ?year contract below).
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
 * Load + parse one year's attendance CSV — or, for the ALL_TIME selection,
 * load every year and merge them into one combined dataset (combineYearData).
 *
 * Each selection is fetched independently so the Dashboard (selected year) and
 * the Wrapped routes (always 2025) can hold separate data without stepping on
 * each other. Re-fetches whenever `year` changes.
 *
 * @param {number|'all'} year - a key in YEARS, or the ALL_TIME sentinel
 * @returns {{ data: object|null, loading: boolean, error: string|null }}
 */
function useYearData(year) {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)

    // All time = every year fetched in parallel, then merged. A single year is
    // just that one fetch. Either way we end with one parsed dataset.
    const work = isAllTime(year)
      ? Promise.all(YEAR_LIST.map(loadYear)).then(combineYearData)
      : loadYear(year)

    work
      .then((parsed) => {
        if (cancelled) return
        setData(parsed)
        setLoading(false)
      })
      .catch((err) => {
        if (cancelled) return
        setError(err.message)
        setLoading(false)
      })

    // Avoid setting state for a stale selection if it changed mid-flight.
    return () => {
      cancelled = true
    }
  }, [year])

  return { data, loading, error }
}

function App() {
  // ?year contract: the selected dashboard year is driven entirely by the URL
  // query param `?year=YYYY`. A future year-switcher control just needs to call
  // setSearchParams({ year }) (or set the param however it likes) and the data
  // layer re-loads. Absent/invalid values fall back to LATEST_YEAR.
  const [searchParams] = useSearchParams()
  const selectedYear = resolveYear(searchParams.get('year'))

  const dashboard = useYearData(selectedYear)
  const wrapped = useYearData(WRAPPED_YEAR)

  // Only block the whole app on the FIRST load (nothing rendered yet). On a year
  // switch we keep the previous data on screen while the new year loads in the
  // background (stale-while-revalidate), so the header switcher doesn't flash the
  // full-screen spinner. Local CSV swaps are near-instant.
  const initialLoading =
    (dashboard.loading && !dashboard.data) || (wrapped.loading && !wrapped.data)
  const error = dashboard.error || wrapped.error

  if (initialLoading) {
    return (
      <div className="min-h-dvh bg-surface flex items-center justify-center">
        <div className="text-center">
          <div className="size-12 border-4 border-ink border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-ink-muted font-medium">Loading run data...</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-dvh bg-surface flex items-center justify-center">
        <div className="text-center text-ink">
          <p className="text-xl font-semibold mb-2">Error loading data</p>
          <p className="text-ink-muted">{error}</p>
        </div>
      </div>
    )
  }

  return (
    <Routes>
      <Route path="/" element={<Dashboard data={dashboard.data} />} />
      <Route path="/dashboard" element={<Dashboard data={dashboard.data} />} />
      <Route path="/run/:runId" element={<RunDetail data={dashboard.data} />} />
      <Route path="/wrapped" element={<Wrapped data={wrapped.data} />} />
      <Route path="/wrapped/:member" element={<Wrapped data={wrapped.data} />} />
      <Route path="/2025wrapped" element={<Wrapped data={wrapped.data} />} />
      <Route path="/2025wrapped/:member" element={<Wrapped data={wrapped.data} />} />
    </Routes>
  )
}

export default App
