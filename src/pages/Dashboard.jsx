import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import Header from '../components/Layout/Header'
import StatsCards from '../components/Dashboard/StatsCards'
import FilterBar from '../components/Dashboard/FilterBar'
import AttendanceChart from '../components/Dashboard/AttendanceChart'
import Leaderboard from '../components/Dashboard/Leaderboard'
import RunTypeBreakdown from '../components/Dashboard/RunTypeBreakdown'
import RunsTable from '../components/Dashboard/RunsTable'

// Clean display names for run types
const runTypeDisplayNames = {
  'Half- Invasion Day': 'Invasion Day (Half Marathon)',
  '10k- Invasion Day': 'Invasion Day (10K)',
  'Mara- Anzac Day': 'ANZAC Day (Marathon)',
  'Half- Anzac Day': 'ANZAC Day (Half Marathon)',
  'Half- Beer Run': 'Beer Run (Half Marathon)',
  'Good Fri Pancake': 'Good Friday Pancake Run',
  'FILAMENT CUP 🏆': 'Filament Cup',
  'N/hood Loop': "N'hood Loop",
}

// Get clean display name for a run type
const getRunTypeDisplayName = (runType) => {
  return runTypeDisplayNames[runType] || runType
}

export default function Dashboard({ data }) {
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
    <div className="min-h-screen bg-cream">
      <Header />

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Stats Cards */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
        >
          <StatsCards
            totalRuns={data.totalRuns}
            totalKm={data.totalClubKm}
            activeMembers={data.leaderboard.filter(m => m.totalRuns > 0).length}
            avgAttendance={data.avgAttendance}
            filteredStats={filteredStats}
            isFiltered={filters.runType !== 'all' || filters.month !== 'all' || filters.location !== 'all'}
          />
        </motion.div>

        {/* Filter Bar */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="mt-8"
        >
          <FilterBar
            filters={filters}
            setFilters={setFilters}
            options={filterOptions}
          />
        </motion.div>

        {/* Leaderboard and Run Type Row */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-8">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
          >
            <Leaderboard leaderboard={data.leaderboard} distanceLeaderboard={data.distanceLeaderboard} />
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4 }}
          >
            <RunTypeBreakdown runsByType={data.runsByType} />
          </motion.div>
        </div>

        {/* Attendance Chart */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5 }}
          className="mt-6"
        >
          <AttendanceChart runs={filteredRuns} />
        </motion.div>

        {/* Runs Table */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.7 }}
          className="mt-6"
        >
          <RunsTable runs={filteredRuns} allRuns={data.runs} />
        </motion.div>
      </main>

      <footer className="bg-navy text-mint py-6 mt-12">
        <div className="max-w-7xl mx-auto px-4 text-center text-sm">
          <p>Filament Coffee Track Club - 2025 Season</p>
          <p className="mt-1 text-cream/60">Keep running, keep caffeinating</p>
        </div>
      </footer>
    </div>
  )
}
