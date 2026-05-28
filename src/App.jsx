import { Routes, Route, useSearchParams } from 'react-router-dom'
import { useState, useEffect } from 'react'
import Dashboard from './pages/Dashboard'
import Wrapped from './pages/Wrapped'
import RunDetail from './pages/RunDetail'
import { parseRunData } from './utils/dataParser'
import { YEARS, resolveYear } from './config/years'

// The 2025 Wrapped retrospective is pinned to 2025 forever, regardless of which
// year the dashboard is currently viewing. The Dashboard/RunDetail routes follow
// the selected year instead (see the ?year contract below).
const WRAPPED_YEAR = 2025

/**
 * Load + parse a single year's attendance CSV.
 *
 * Each year is fetched independently so the Dashboard (selected year) and the
 * Wrapped routes (always 2025) can hold separate data without stepping on each
 * other. Re-fetches whenever `year` changes.
 *
 * @param {number} year - a key in YEARS
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

    fetch(YEARS[year])
      .then((response) => {
        // fetch only rejects on network errors, not HTTP errors (e.g. a 404 for
        // a missing per-year CSV), so surface those explicitly.
        if (!response.ok) {
          throw new Error(`Failed to load ${year} data (HTTP ${response.status})`)
        }
        return response.text()
      })
      .then((csv) => {
        if (cancelled) return
        setData(parseRunData(csv, year))
        setLoading(false)
      })
      .catch((err) => {
        if (cancelled) return
        setError(err.message)
        setLoading(false)
      })

    // Avoid setting state for a stale year if the selection changed mid-flight.
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
