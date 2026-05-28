// Clean filter bar: white card, hairline-bordered selects, muted labels.
// The "Clear Filters" action uses the single dark accent when active.
export default function FilterBar({ filters, setFilters, options }) {
  const handleChange = (key, value) => {
    setFilters(prev => ({ ...prev, [key]: value }))
  }

  const clearFilters = () => {
    setFilters({ runType: 'all', month: 'all', location: 'all' })
  }

  const hasActiveFilters = filters.runType !== 'all' || filters.month !== 'all' || filters.location !== 'all'

  const selectClass = "px-3 py-2 rounded-lg border border-border bg-card text-ink text-sm focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-shadow"

  return (
    <div className="card-clean p-4">
      <div className="flex flex-wrap items-center gap-4">
        <div className="flex items-center gap-2 text-ink-muted">
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
          </svg>
          <span className="font-medium text-sm text-ink">Filters</span>
        </div>

        <div className="flex flex-wrap gap-3 flex-1">
          <select
            value={filters.runType}
            onChange={(e) => handleChange('runType', e.target.value)}
            className={selectClass}
          >
            <option value="all">All Run Types</option>
            {options.runTypes.map(type => (
              <option key={type.value} value={type.value}>{type.label}</option>
            ))}
          </select>

          <select
            value={filters.month}
            onChange={(e) => handleChange('month', e.target.value)}
            className={selectClass}
          >
            <option value="all">All Months</option>
            {options.months.map(month => (
              <option key={month} value={month}>{month}</option>
            ))}
          </select>

          <select
            value={filters.location}
            onChange={(e) => handleChange('location', e.target.value)}
            className={selectClass}
          >
            <option value="all">All Locations</option>
            {options.locations.map(loc => (
              <option key={loc} value={loc}>{loc}</option>
            ))}
          </select>
        </div>

        {hasActiveFilters && (
          <button
            onClick={clearFilters}
            className="px-4 py-2 text-sm font-medium text-card bg-accent hover:bg-ink rounded-lg transition-colors"
          >
            Clear Filters
          </button>
        )}
      </div>
    </div>
  )
}
