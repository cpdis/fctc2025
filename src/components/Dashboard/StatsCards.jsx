// KPI stat strip: one bordered surface with the four metrics separated by
// dividers (a 2x2 grid with dividers on mobile, a single divided row on
// desktop). No icons and no per-card boxes, per the dashboard/surfaces
// guidelines. Color restraint: numerals in ink, labels and suffixes muted grey.
export default function StatsCards({ totalRuns, totalKm, activeMembers, avgAttendance, filteredStats, isFiltered }) {
  const stats = [
    {
      label: 'Total Runs',
      value: isFiltered ? filteredStats.totalRuns : totalRuns,
      fullValue: totalRuns,
    },
    {
      label: 'Aggregate Distance',
      value: isFiltered ? `${filteredStats.totalKm.toFixed(0)}` : `${totalKm.toFixed(0)}`,
      fullValue: totalKm.toFixed(0),
      suffix: 'km',
    },
    {
      label: 'Active Members',
      value: activeMembers,
    },
    {
      label: 'Avg Attendance',
      value: isFiltered ? filteredStats.avgAttendance.toFixed(1) : avgAttendance.toFixed(1),
      fullValue: avgAttendance.toFixed(1),
      suffix: '/run',
    },
  ]

  // Dividers via nth-child so they reconfigure across breakpoints: 2-col mobile
  // (left border on col 2, top border on row 2) becomes a 4-col row on desktop
  // (left border on every item but the first, no row border).
  const dividers =
    'border-border [&:nth-child(2n)]:border-l [&:nth-child(n+3)]:border-t ' +
    'lg:[&:nth-child(n+3)]:border-t-0 lg:[&:not(:nth-child(4n+1))]:border-l'

  return (
    <div className="card-clean grid grid-cols-2 lg:grid-cols-4">
      {stats.map((stat) => (
        <div key={stat.label} className={`p-5 ${dividers}`}>
          <p className="flex items-baseline gap-1">
            <span className="font-display text-3xl font-semibold text-ink tracking-tight tabular-nums">
              {stat.value}
            </span>
            {stat.suffix && <span className="text-base text-ink-muted">{stat.suffix}</span>}
          </p>
          <p className="text-sm text-ink-muted mt-1 truncate">
            {stat.label}
            {isFiltered && stat.fullValue != null && (
              <span className="text-ink-muted/70"> of {stat.fullValue}</span>
            )}
          </p>
        </div>
      ))}
    </div>
  )
}
