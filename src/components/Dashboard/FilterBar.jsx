export default function FilterBar({ filters, setFilters, options }) {
  const handleChange = (key, value) => {
    setFilters(prev => ({ ...prev, [key]: value }))
  }

  const clearFilters = () => {
    setFilters({ runType: 'all', month: 'all', location: 'all' })
  }

  const hasActiveFilters = filters.runType !== 'all' || filters.month !== 'all' || filters.location !== 'all'

  return (
    <div className="bg-white rounded-2xl shadow-md p-4">
      <div className="flex flex-wrap items-center gap-4">
        <div className="flex items-center gap-2">
          <svg className="w-5 h-5 text-coffee" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
          </svg>
          <span className="font-medium text-espresso">Filters</span>
        </div>

        <div className="flex flex-wrap gap-3 flex-1">
          <select
            value={filters.runType}
            onChange={(e) => handleChange('runType', e.target.value)}
            className="px-4 py-2 rounded-lg border border-latte bg-cream text-roast focus:outline-none focus:ring-2 focus:ring-coffee focus:border-transparent"
          >
            <option value="all">All Run Types</option>
            {options.runTypes.map(type => (
              <option key={type.value} value={type.value}>{type.label}</option>
            ))}
          </select>

          <select
            value={filters.month}
            onChange={(e) => handleChange('month', e.target.value)}
            className="px-4 py-2 rounded-lg border border-latte bg-cream text-roast focus:outline-none focus:ring-2 focus:ring-coffee focus:border-transparent"
          >
            <option value="all">All Months</option>
            {options.months.map(month => (
              <option key={month} value={month}>{month}</option>
            ))}
          </select>

          <select
            value={filters.location}
            onChange={(e) => handleChange('location', e.target.value)}
            className="px-4 py-2 rounded-lg border border-latte bg-cream text-roast focus:outline-none focus:ring-2 focus:ring-coffee focus:border-transparent"
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
            className="px-4 py-2 text-sm font-medium text-terracotta hover:text-white hover:bg-terracotta rounded-lg transition-colors border border-terracotta"
          >
            Clear Filters
          </button>
        )}
      </div>
    </div>
  )
}
