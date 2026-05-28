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

  // Wait for both data sets so every route has what it needs. (When the selected
  // year IS 2025 these are two fetches of the same file; that's cheap and keeps
  // the wiring dead simple.)
  const loading = dashboard.loading || wrapped.loading
  const error = dashboard.error || wrapped.error

  if (loading) {
    return (
      <div className="min-h-screen bg-cream flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-coffee border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-coffee font-medium">Loading run data...</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-screen bg-cream flex items-center justify-center">
        <div className="text-center text-terracotta">
          <p className="text-xl font-bold mb-2">Error loading data</p>
          <p>{error}</p>
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
