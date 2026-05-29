import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { getRunTypeDisplayName, dataColors } from '../../utils/theme'
import { runTypeColorMap, tint } from '../../utils/runTypeColors'

export default function RunsTable({ runs, allRuns, runsByType = {} }) {
  const navigate = useNavigate()
  // Badge tints match the Run Type Distribution donut (same color per type).
  const typeColors = useMemo(() => runTypeColorMap(runsByType), [runsByType])
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

  // SVG sort indicator: a stacked up/down chevron pair. The inactive column
  // shows both chevrons muted; the active column highlights the chevron for the
  // current direction. Drawn as SVG (not unicode arrows, which iOS renders as
  // coloured emoji) so it stays a quiet monochrome glyph.
  const SortIcon = ({ columnKey }) => {
    const active = sortConfig.key === columnKey
    const dir = active ? sortConfig.direction : null
    return (
      <svg
        className="inline-block ml-1.5 -mt-0.5 h-3 w-3 align-middle"
        viewBox="0 0 10 14"
        fill="none"
        aria-hidden="true"
      >
        <path
          d="M5 1L8 5H2L5 1Z"
          className={dir === 'asc' ? 'fill-ink' : 'fill-ink-muted/40'}
        />
        <path
          d="M5 13L2 9H8L5 13Z"
          className={dir === 'desc' ? 'fill-ink' : 'fill-ink-muted/40'}
        />
      </svg>
    )
  }

  const thClass = "px-4 sm:px-6 py-3 text-left text-xs font-medium text-ink-muted uppercase tracking-wider cursor-pointer hover:text-ink transition-colors select-none whitespace-nowrap"

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
              <th onClick={() => handleSort('meet')} className={`${thClass} hidden md:table-cell`}>
                Location <SortIcon columnKey="meet" />
              </th>
              <th onClick={() => handleSort('actualKm')} className={`${thClass} hidden sm:table-cell`}>
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
                <td className="px-4 sm:px-6 py-3 whitespace-nowrap text-sm text-ink">
                  {run.date}
                </td>
                <td className="px-4 sm:px-6 py-3 whitespace-nowrap">
                  {(() => {
                    const c = typeColors[run.runType] || '#78716c'
                    return (
                      <span
                        className="px-2.5 py-1 rounded-md text-xs font-medium text-ink border"
                        style={{ backgroundColor: tint(c, 0.14), borderColor: tint(c, 0.35) }}
                      >
                        {getRunTypeDisplayName(run.runType)}
                      </span>
                    )
                  })()}
                </td>
                <td className="hidden md:table-cell px-4 sm:px-6 py-3 whitespace-nowrap text-sm text-ink-muted">
                  {run.meet}
                </td>
                <td className="hidden sm:table-cell px-4 sm:px-6 py-3 whitespace-nowrap text-sm font-medium text-ink tabular-nums">
                  {run.actualKm ? `${run.actualKm.toFixed(2)} km` : '-'}
                </td>
                <td className="px-4 sm:px-6 py-3 whitespace-nowrap">
                  <div className="flex items-center gap-3">
                    <span className="text-sm font-semibold text-ink w-6 tabular-nums">{run.totalAttendance}</span>
                    <div className="w-16 sm:w-20 h-1.5 rounded-full overflow-hidden bg-border">
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

      <div className="px-4 sm:px-6 py-4 border-t border-border text-sm text-ink-muted">
        Showing {sortedRuns.length} of {runs.length} runs
      </div>
    </div>
  )
}
