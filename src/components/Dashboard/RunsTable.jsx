import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import { useNavigate } from 'react-router-dom'
import { getRunTypeDisplayName, dataColors } from '../../utils/theme'

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
      return <span className="text-ink-muted/40 ml-1">↕</span>
    }
    return <span className="text-ink ml-1">{sortConfig.direction === 'asc' ? '↑' : '↓'}</span>
  }

  const thClass = "px-6 py-3 text-left text-xs font-medium text-ink-muted uppercase tracking-wider cursor-pointer hover:text-ink transition-colors select-none"

  return (
    <div className="card-clean overflow-hidden">
      <div className="p-6 border-b border-border">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <h3 className="font-display text-lg font-semibold text-ink">Run History</h3>

          <div className="relative">
            <input
              type="text"
              placeholder="Search runs, locations, members..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full sm:w-72 pl-10 pr-4 py-2 rounded-lg border border-border bg-card text-ink text-sm placeholder:text-ink-muted/60 focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-shadow"
            />
            <svg className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-muted" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-surface">
            <tr>
              <th onClick={() => handleSort('parsedDate')} className={thClass}>
                Date <SortIcon columnKey="parsedDate" />
              </th>
              <th onClick={() => handleSort('runType')} className={thClass}>
                Run Type <SortIcon columnKey="runType" />
              </th>
              <th onClick={() => handleSort('meet')} className={thClass}>
                Location <SortIcon columnKey="meet" />
              </th>
              <th onClick={() => handleSort('actualKm')} className={thClass}>
                Distance <SortIcon columnKey="actualKm" />
              </th>
              <th onClick={() => handleSort('totalAttendance')} className={thClass}>
                Attendance <SortIcon columnKey="totalAttendance" />
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {sortedRuns.map((run) => {
              // Find the original index in allRuns for navigation
              const originalIndex = allRuns.findIndex(r => r.date === run.date && r.runType === run.runType)

              return (
              <tr
                key={`${run.date}-${run.runType}`}
                onClick={() => navigate(`/run/${originalIndex}`)}
                className="hover:bg-surface cursor-pointer transition-colors"
              >
                <td className="px-6 py-3 whitespace-nowrap text-sm text-ink">
                  {run.date}
                </td>
                <td className="px-6 py-3 whitespace-nowrap">
                  <span className="px-2.5 py-1 rounded-md text-xs font-medium text-ink bg-surface border border-border">
                    {getRunTypeDisplayName(run.runType)}
                  </span>
                </td>
                <td className="px-6 py-3 whitespace-nowrap text-sm text-ink-muted">
                  {run.meet}
                </td>
                <td className="px-6 py-3 whitespace-nowrap text-sm font-medium text-ink tabular-nums">
                  {run.actualKm ? `${run.actualKm.toFixed(2)} km` : '-'}
                </td>
                <td className="px-6 py-3 whitespace-nowrap">
                  <div className="flex items-center gap-3">
                    <span className="text-sm font-semibold text-ink w-6 tabular-nums">{run.totalAttendance}</span>
                    <div className="w-20 h-1.5 rounded-full overflow-hidden bg-border">
                      <div
                        className="h-full rounded-full"
                        style={{
                          width: `${Math.min((run.totalAttendance / 20) * 100, 100)}%`,
                          background: dataColors[0]
                        }}
                      />
                    </div>
                  </div>
                </td>
              </tr>
            )})}
          </tbody>
        </table>
      </div>

      {sortedRuns.length === 0 && (
        <div className="p-12 text-center text-ink-muted">
          No runs found matching your search.
        </div>
      )}

      <div className="px-6 py-4 border-t border-border text-sm text-ink-muted">
        Showing {sortedRuns.length} of {runs.length} runs
      </div>
    </div>
  )
}
