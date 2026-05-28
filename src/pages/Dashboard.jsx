import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import { useSearchParams } from 'react-router-dom'
import Header from '../components/Layout/Header'
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
import { resolveYear } from '../config/years'

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
  // The footer season label follows the selected year (?year), same source the
  // Header switcher writes to.
  const [searchParams] = useSearchParams()
  const selectedYear = resolveYear(searchParams.get('year'))

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
    // Page-level near-white background. Set here (not on global body) so the
    // Wrapped experience keeps its own cream background.
    <div className="min-h-screen bg-surface text-ink">
      <Header />

      <motion.main
        variants={container}
        initial="hidden"
        animate="visible"
        className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8"
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

        {/* Leaderboard and Run Type Row */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-8">
          <motion.div variants={item}>
            <Leaderboard leaderboard={data.leaderboard} distanceLeaderboard={data.distanceLeaderboard} />
          </motion.div>

          <motion.div variants={item}>
            <RunTypeBreakdown runsByType={data.runsByType} />
          </motion.div>
        </div>

        {/* Attendance Chart */}
        <motion.div variants={item} className="mt-6">
          <AttendanceChart runs={filteredRuns} />
        </motion.div>

        {/* Runs Table */}
        <motion.div variants={item} className="mt-6">
          <RunsTable runs={filteredRuns} allRuns={data.runs} runsByType={data.runsByType} />
        </motion.div>
      </motion.main>

      <footer className="border-t border-border mt-12 py-6">
        <div className="max-w-7xl mx-auto px-4 text-center text-sm text-ink-muted">
          <p>Filament Coffee Track Club, {selectedYear} Season</p>
          <p className="mt-1">Keep running, keep caffeinating</p>
        </div>
      </footer>
    </div>
  )
}
