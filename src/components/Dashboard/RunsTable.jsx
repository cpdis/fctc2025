import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import { useNavigate } from 'react-router-dom'

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
      return <span className="text-latte ml-1">↕</span>
    }
    return <span className="text-terracotta ml-1">{sortConfig.direction === 'asc' ? '↑' : '↓'}</span>
  }

  return (
    <div className="bg-white rounded-2xl shadow-md overflow-hidden">
      <div className="p-6 border-b border-cream-dark">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <h3 className="text-lg font-bold text-espresso">Run History</h3>

          <div className="relative">
            <input
              type="text"
              placeholder="Search runs, locations, members..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full sm:w-64 pl-10 pr-4 py-2 rounded-lg border border-latte bg-cream text-roast placeholder:text-coffee/40 focus:outline-none focus:ring-2 focus:ring-coffee focus:border-transparent"
            />
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-coffee/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-cream-dark">
            <tr>
              <th
                onClick={() => handleSort('parsedDate')}
                className="px-6 py-3 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-latte/30"
              >
                Date <SortIcon columnKey="parsedDate" />
              </th>
              <th
                onClick={() => handleSort('runType')}
                className="px-6 py-3 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-latte/30"
              >
                Run Type <SortIcon columnKey="runType" />
              </th>
              <th
                onClick={() => handleSort('meet')}
                className="px-6 py-3 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-latte/30"
              >
                Location <SortIcon columnKey="meet" />
              </th>
              <th
                onClick={() => handleSort('actualKm')}
                className="px-6 py-3 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-latte/30"
              >
                Distance <SortIcon columnKey="actualKm" />
              </th>
              <th
                onClick={() => handleSort('totalAttendance')}
                className="px-6 py-3 text-left text-xs font-semibold text-coffee uppercase tracking-wider cursor-pointer hover:bg-latte/30"
              >
                Attendance <SortIcon columnKey="totalAttendance" />
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-cream-dark">
            {sortedRuns.map((run, index) => {
              // Find the original index in allRuns for navigation
              const originalIndex = allRuns.findIndex(r => r.date === run.date && r.runType === run.runType)
              return (
              <motion.tr
                key={`${run.date}-${run.runType}`}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: index * 0.02 }}
                onClick={() => navigate(`/run/${originalIndex}`)}
                className="hover:bg-cream cursor-pointer"
              >
                <td className="px-6 py-4 whitespace-nowrap text-sm text-espresso">
                  {run.date}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span className="px-2.5 py-1 rounded-full text-xs font-medium bg-latte/50 text-coffee">
                    {run.runType}
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-coffee">
                  {run.meet}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-espresso">
                  {run.actualKm ? `${run.actualKm.toFixed(2)} km` : '-'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-bold text-espresso">{run.totalAttendance}</span>
                    <div className="w-16 h-2 bg-cream-dark rounded-full overflow-hidden">
                      <div
                        className="h-full bg-terracotta rounded-full"
                        style={{ width: `${Math.min((run.totalAttendance / 20) * 100, 100)}%` }}
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
        <div className="p-12 text-center text-coffee/60">
          No runs found matching your search.
        </div>
      )}

      <div className="px-6 py-4 border-t border-cream-dark text-sm text-coffee/70">
        Showing {sortedRuns.length} of {runs.length} runs
      </div>
    </div>
  )
}
