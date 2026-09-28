import { useState, useMemo, useEffect } from 'react'
import { motion } from 'framer-motion'
import { useSearchParams } from 'react-router-dom'
import SiteHeader from '../components/Poster/SiteHeader'
import SeasonTitle from '../components/Poster/SeasonTitle'
import SiteFooter from '../components/Poster/SiteFooter'
import StatsCards from '../components/Dashboard/StatsCards'
import FilterBar from '../components/Dashboard/FilterBar'
import AttendanceChart from '../components/Dashboard/AttendanceChart'
import Leaderboard from '../components/Dashboard/Leaderboard'
import RunTypeBreakdown from '../components/Dashboard/RunTypeBreakdown'
import RunsTable from '../components/Dashboard/RunsTable'
import SeasonProgress from '../components/Dashboard/viz/SeasonProgress'
import SparklineLeaderboard from '../components/Dashboard/viz/SparklineLeaderboard'
import CalendarHeatmap from '../components/Dashboard/viz/CalendarHeatmap'
import HalfSeasonSlopegraph from '../components/Dashboard/viz/HalfSeasonSlopegraph'
import RunTypeSmallMultiples from '../components/Dashboard/viz/RunTypeSmallMultiples'
import { getRunTypeDisplayName } from '../utils/theme'
import { resolveYear, isAllTime } from '../config/years'
import { yearSwitchParams } from '../utils/dashboardPaths'

// One restrained staggered reveal for the whole page: a single subtle
// fade + small upward translate per section, children offset by a small delay.
// This replaces the old per-element spring/scale animations (chartjunk for the
// eye). Keep it quiet.
const container = {
  hidden: { opacity: 1 },
  visible: { transition: { staggerChildren: 0.06 } },
}

const item = {
  hidden: { opacity: 0, y: 12 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.35, ease: 'easeOut' } },
}

export default function Dashboard({ data }) {
  // The selected season lives in ?year; the title band's year control writes
  // it. The footer label is "All Time" for the combined view, else
  // "<year> Season".
  const [searchParams, setSearchParams] = useSearchParams()
  const selectedYear = resolveYear(searchParams.get('year'))
  const seasonLabel = isAllTime(selectedYear) ? 'All Time' : `${selectedYear} Season`

  // A new season is a new view, so the run-log filters reset (AE7).
  const selectYear = (year) => setSearchParams(yearSwitchParams(searchParams, year))

  // The meta row's last run: the latest by date, since All time concatenates
  // seasons newest first rather than in date order.
  const lastRun = useMemo(() => {
    if (data.runs.length === 0) return null
    const latest = data.runs.reduce((a, b) => (b.parsedDate > a.parsedDate ? b : a))
    return { date: latest.parsedDate, location: latest.location, type: latest.type }
  }, [data.runs])

  // "Updated" timestamp, stamped by the weekly data-sync GitHub Action
  // whenever it commits fresh data (see .github/workflows/weekly-data-sync.yml).
  // Rendered in the viewer's local timezone. Fetched best-effort: if the file is
  // missing or malformed the meta row simply leaves it out.
  const [lastUpdated, setLastUpdated] = useState(null)
  useEffect(() => {
    let cancelled = false
    fetch('/data/last-updated.json')
      .then((res) => (res.ok ? res.json() : null))
      .then((json) => {
        const ts = json?.updatedAt ? new Date(json.updatedAt) : null
        if (!cancelled && ts && !Number.isNaN(ts.getTime())) setLastUpdated(ts)
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [])

  const [filters, setFilters] = useState({
    runType: 'all',
    month: 'all',
    location: 'all'
  })

  // Get unique values for filters
  const filterOptions = useMemo(() => {
    const runTypesRaw = [...new Set(data.runs.map(r => r.runType))].sort()
    // Create objects with value and display name
    const runTypes = runTypesRaw.map(type => ({
      value: type,
      label: getRunTypeDisplayName(type)
    })).sort((a, b) => a.label.localeCompare(b.label))

    const locations = [...new Set(data.runs.map(r => r.meet))].sort()
    const months = [...new Set(data.runs
      .filter(r => r.parsedDate)
      .map(r => r.parsedDate.toLocaleString('default', { month: 'short' }))
    )]
    return { runTypes, locations, months }
  }, [data])

  // Filter runs based on selected filters
  const filteredRuns = useMemo(() => {
    return data.runs.filter(run => {
      if (filters.runType !== 'all' && run.runType !== filters.runType) return false
      if (filters.location !== 'all' && run.meet !== filters.location) return false
      if (filters.month !== 'all' && run.parsedDate) {
        const month = run.parsedDate.toLocaleString('default', { month: 'short' })
        if (month !== filters.month) return false
      }
      return true
    })
  }, [data.runs, filters])

  // Recalculate stats based on filtered data
  const filteredStats = useMemo(() => {
    const totalRuns = filteredRuns.length
    const totalKm = filteredRuns.reduce((sum, r) => sum + (r.actualKm || 0), 0)
    const totalAttendance = filteredRuns.reduce((sum, r) => sum + r.totalAttendance, 0)
    const avgAttendance = totalRuns > 0 ? totalAttendance / totalRuns : 0

    return { totalRuns, totalKm, totalAttendance, avgAttendance }
  }, [filteredRuns])

  return (
    // The .poster root scopes the fctc.fun brand tokens and fonts
    // (styles/poster.css), so Wrapped keeps its own palette.
    <div className="poster">
      <SiteHeader year={selectedYear} />

      <main>
        <div className="wrap">
          <SeasonTitle
            year={selectedYear}
            onSelectYear={selectYear}
            updatedAt={lastUpdated}
            lastRun={lastRun}
          />
        </div>

        <motion.div
          variants={container}
          initial="hidden"
          animate="visible"
          className="max-w-7xl 2xl:max-w-[1680px] mx-auto px-4 sm:px-6 lg:px-8 py-8"
        >
          {/* Stats Cards */}
          <motion.div variants={item}>
            <StatsCards
              totalRuns={data.totalRuns}
              totalKm={data.totalClubKm}
              activeMembers={data.leaderboard.filter(m => m.totalRuns > 0).length}
              avgAttendance={data.avgAttendance}
              filteredStats={filteredStats}
              isFiltered={filters.runType !== 'all' || filters.month !== 'all' || filters.location !== 'all'}
            />
          </motion.div>

          {/* Season Progress — cumulative distance, sits with the headline stats. */}
          <motion.div variants={item} className="mt-6">
            <SeasonProgress data={data} />
          </motion.div>

          {/* Sparkline leaderboard — high-density centerpiece, whole season per member. */}
          <motion.div variants={item} className="mt-6">
            <SparklineLeaderboard data={data} />
          </motion.div>

          {/* Calendar heatmap + half-season slopegraph as a paired insight row. */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
            <motion.div variants={item}>
              <CalendarHeatmap data={data} year={selectedYear} />
            </motion.div>
            <motion.div variants={item}>
              <HalfSeasonSlopegraph data={data} />
            </motion.div>
          </div>

          {/* Run-type small multiples — seasonality across types, shared y-scale. */}
          <motion.div variants={item} className="mt-6">
            <RunTypeSmallMultiples data={data} />
          </motion.div>

          {/* Filter Bar */}
          <motion.div variants={item} className="mt-8">
            <FilterBar
              filters={filters}
              setFilters={setFilters}
              options={filterOptions}
            />
          </motion.div>

          {/* Leaderboard, run-type distribution and the attendance chart. Two-up
              from lg; three-up at very wide widths. All three are similar height so
              the row balances cleanly. Attendance spans full width at lg (its own
              row) and folds into the trio only at 2xl, so the sub-2xl layout is
              unchanged. */}
          <div className="grid grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3 gap-6 mt-8">
            <motion.div variants={item}>
              <Leaderboard leaderboard={data.leaderboard} distanceLeaderboard={data.distanceLeaderboard} />
            </motion.div>

            <motion.div variants={item}>
              <RunTypeBreakdown runsByType={data.runsByType} />
            </motion.div>

            <motion.div variants={item} className="lg:col-span-2 2xl:col-span-1">
              <AttendanceChart runs={filteredRuns} />
            </motion.div>
          </div>

          {/* Run history — full width: a wide, dense table uses the room well. */}
          <motion.div variants={item} className="mt-6">
            <RunsTable runs={filteredRuns} runsByType={data.runsByType} />
          </motion.div>
        </motion.div>
      </main>

      <SiteFooter seasonLabel={seasonLabel} />
    </div>
  )
}
