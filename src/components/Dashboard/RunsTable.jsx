import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import { useNavigate } from 'react-router-dom'
import { runTypeColors, colors, getRunTypeDisplayName } from '../../utils/theme'

export default function RunsTable({ runs, allRuns }) {
  const navigate = useNavigate()
  const [sortConfig, setSortConfig] = useState({ key: 'parsedDate', direction: 'desc' })
  const [searchTerm, setSearchTerm] = useState('')

  const sortedRuns = useMemo(() => {
    let filteredRuns = runs

    // Apply search filter
    if (searchTerm) {
      const term = searchTerm.toLowerCase()
      filteredRuns = runs.filter(run =>
        run.runType.toLowerCase().includes(term) ||
        run.meet.toLowerCase().includes(term) ||
        run.date.toLowerCase().includes(term) ||
        run.attendees.some(a => a.toLowerCase().includes(term))
      )
    }

    // Apply sorting
    return [...filteredRuns].sort((a, b) => {
      let aVal = a[sortConfig.key]
      let bVal = b[sortConfig.key]

      if (sortConfig.key === 'parsedDate') {
        aVal = a.parsedDate?.getTime() || 0
        bVal = b.parsedDate?.getTime() || 0
      }

      if (aVal < bVal) return sortConfig.direction === 'asc' ? -1 : 1
      if (aVal > bVal) return sortConfig.direction === 'asc' ? 1 : -1
      return 0
    })
  }, [runs, sortConfig, searchTerm])

  const handleSort = (key) => {
    setSortConfig(prev => ({
      key,
      direction: prev.key === key && prev.direction === 'asc' ? 'desc' : 'asc'
    }))
  }

  const SortIcon = ({ columnKey }) => {
    if (sortConfig.key !== columnKey) {
      return <span className="text-coffee/30 ml-1">↕</span>
    }
    return <span className="text-terracotta ml-1">{sortConfig.direction === 'asc' ? '↑' : '↓'}</span>
  }

  return (
    <div
      className="bg-white rounded-2xl overflow-hidden relative"
      style={{
        boxShadow: `
          0 1px 2px rgba(2, 9, 18, 0.04),
          0 4px 12px rgba(2, 9, 18, 0.06)
        `
      }}
    >
      {/* Subtle accent line */}
      <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-amber via-terracotta to-pink opacity-50" />

      <div className="p-6 border-b border-cream">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <h3 className="font-display text-lg font-bold text-espresso">Run History</h3>

          <div className="relative">
            <input
              type="text"
              placeholder="Search runs, locations, members..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full sm:w-72 pl-10 pr-4 py-2.5 rounded-xl border-0 bg-cream text-roast placeholder:text-coffee/40 focus:outline-none focus:ring-2 focus:ring-amber/50 transition-shadow"
            />
            <svg className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-coffee/40" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-cream/50">
            <tr>
              <th
                onClick={() => handleSort('parsedDate')}
                className="px-6 py-4 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-cream/80 transition-colors"
              >
                Date <SortIcon columnKey="parsedDate" />
              </th>
              <th
                onClick={() => handleSort('runType')}
                className="px-6 py-4 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-cream/80 transition-colors"
              >
                Run Type <SortIcon columnKey="runType" />
              </th>
              <th
                onClick={() => handleSort('meet')}
                className="px-6 py-4 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-cream/80 transition-colors"
              >
                Location <SortIcon columnKey="meet" />
              </th>
              <th
                onClick={() => handleSort('actualKm')}
                className="px-6 py-4 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-cream/80 transition-colors"
              >
                Distance <SortIcon columnKey="actualKm" />
              </th>
              <th
                onClick={() => handleSort('totalAttendance')}
                className="px-6 py-4 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-cream/80 transition-colors"
              >
                Attendance <SortIcon columnKey="totalAttendance" />
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-cream">
            {sortedRuns.map((run, index) => {
              // Find the original index in allRuns for navigation
              const originalIndex = allRuns.findIndex(r => r.date === run.date && r.runType === run.runType)
              const runColor = runTypeColors[run.runType] || colors.coffee

              return (
              <motion.tr
                key={`${run.date}-${run.runType}`}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: Math.min(index * 0.01, 0.3) }}
                onClick={() => navigate(`/run/${originalIndex}`)}
                className="hover:bg-cream/30 cursor-pointer transition-colors group"
              >
                <td className="px-6 py-4 whitespace-nowrap text-sm text-espresso font-medium">
                  {run.date}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span
                    className="px-3 py-1.5 rounded-lg text-xs font-semibold text-white"
                    style={{
                      backgroundColor: runColor,
                      boxShadow: `0 2px 4px ${runColor}30`
                    }}
                  >
                    {getRunTypeDisplayName(run.runType)}
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-coffee">
                  {run.meet}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-display font-semibold text-espresso">
                  {run.actualKm ? `${run.actualKm.toFixed(2)} km` : '-'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="flex items-center gap-3">
                    <span className="font-display text-sm font-bold text-espresso w-6">{run.totalAttendance}</span>
                    <div className="w-20 h-2.5 bg-cream rounded-full overflow-hidden">
                      <motion.div
                        initial={{ width: 0 }}
                        animate={{ width: `${Math.min((run.totalAttendance / 20) * 100, 100)}%` }}
                        transition={{ duration: 0.4, delay: Math.min(index * 0.02, 0.5) }}
                        className="h-full rounded-full"
                        style={{
                          background: `linear-gradient(90deg, ${runColor}90, ${runColor})`,
                          borderRadius: '9999px 8px 6px 9999px'
                        }}
                      />
                    </div>
                  </div>
                </td>
              </motion.tr>
            )})}
          </tbody>
        </table>
      </div>

      {sortedRuns.length === 0 && (
        <div className="p-12 text-center">
          <div className="text-4xl mb-3">🔍</div>
          <div className="text-coffee/60 font-medium">No runs found matching your search.</div>
        </div>
      )}

      <div className="px-6 py-4 border-t border-cream text-sm text-coffee/60 font-medium">
        Showing {sortedRuns.length} of {runs.length} runs
      </div>
    </div>
  )
}
