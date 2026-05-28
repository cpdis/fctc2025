// Clean stat cards: white surface, hairline border, muted icon, ink numerals.
// No gradients, no per-card spring animations (the page-level reveal handles
// entrance). Color restraint: numerals in ink, labels/suffixes muted grey.
export default function StatsCards({ totalRuns, totalKm, activeMembers, avgAttendance, filteredStats, isFiltered }) {
  const stats = [
    {
      label: 'Total Runs',
      value: isFiltered ? filteredStats.totalRuns : totalRuns,
      fullValue: totalRuns,
      icon: (
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
        </svg>
      ),
    },
    {
      label: 'Aggregate Distance',
      value: isFiltered ? `${filteredStats.totalKm.toFixed(0)}` : `${totalKm.toFixed(0)}`,
      fullValue: totalKm.toFixed(0),
      suffix: 'km',
      icon: (
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
        </svg>
      ),
    },
    {
      label: 'Active Members',
      value: activeMembers,
      icon: (
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
        </svg>
      ),
    },
    {
      label: 'Avg Attendance',
      value: isFiltered ? filteredStats.avgAttendance.toFixed(1) : avgAttendance.toFixed(1),
      fullValue: avgAttendance.toFixed(1),
      suffix: '/run',
      icon: (
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        </svg>
      ),
    }
  ]

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
      {stats.map((stat) => (
        <div key={stat.label} className="card-clean p-5">
          <div className="flex items-center justify-between mb-3">
            <span className="text-ink-muted">{stat.icon}</span>
            {isFiltered && stat.fullValue && (
              <span className="text-xs text-ink-muted">of {stat.fullValue}</span>
            )}
          </div>
          <div>
            <span className="font-display text-3xl font-semibold text-ink tracking-tight tabular-nums">
              {stat.value}
            </span>
            {stat.suffix && (
              <span className="text-base text-ink-muted ml-1">{stat.suffix}</span>
            )}
          </div>
          <p className="text-sm text-ink-muted mt-1">{stat.label}</p>
        </div>
      ))}
    </div>
  )
}
