import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts'
import { getRunTypeDisplayName } from '../../utils/theme'
import { palette, tooltipContentStyle } from '../../utils/chartConfig'

// Number of top run types to show individually (rest become "Special Events")
const TOP_TYPES_COUNT = 6

// Restrained ground: cycle the dataColors palette by slice index instead of
// per-run-type hue. Color carries order/weight, not category identity, so the
// donut reads as one quiet object rather than a rainbow.
const sliceColor = (index) => palette[index % palette.length]

export default function RunTypeBreakdown({ runsByType }) {
  const allData = Object.entries(runsByType)
    .map(([type, stats]) => ({
      name: getRunTypeDisplayName(type),
      rawName: type,
      value: stats.count,
      km: stats.totalKm,
      attendance: stats.totalAttendance
    }))
    .sort((a, b) => b.value - a.value)

  // Take top types and combine the rest into "Special Events"
  const topTypes = allData.slice(0, TOP_TYPES_COUNT)
  const otherTypes = allData.slice(TOP_TYPES_COUNT)

  // Combine "other" types into Special Events
  const specialEvents = otherTypes.length > 0 ? {
    name: 'Special Events',
    value: otherTypes.reduce((sum, item) => sum + item.value, 0),
    km: otherTypes.reduce((sum, item) => sum + item.km, 0),
    attendance: otherTypes.reduce((sum, item) => sum + item.attendance, 0),
    isSpecialEvents: true,
    includedTypes: otherTypes.map(t => t.name)
  } : null

  const chartData = specialEvents ? [...topTypes, specialEvents] : topTypes

  const totalRuns = chartData.reduce((sum, item) => sum + item.value, 0)

  const renderCustomLabel = ({ cx, cy, midAngle, innerRadius, outerRadius, percent }) => {
    if (percent < 0.06) return null // Don't show labels for small slices

    const RADIAN = Math.PI / 180
    const radius = innerRadius + (outerRadius - innerRadius) * 0.5
    const x = cx + radius * Math.cos(-midAngle * RADIAN)
    const y = cy + radius * Math.sin(-midAngle * RADIAN)

    return (
      <text
        x={x}
        y={y}
        fill="#ffffff"
        textAnchor="middle"
        dominantBaseline="central"
        fontSize={11}
        fontWeight="600"
        fontFamily="var(--font-sans)"
      >
        {`${(percent * 100).toFixed(0)}%`}
      </text>
    )
  }

  return (
    <div className="card-clean p-6 h-full flex flex-col">
      <h3 className="font-display text-lg font-semibold text-ink mb-4">Run Type Distribution</h3>

      <div className="flex-1 min-h-64">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={chartData}
              cx="50%"
              cy="50%"
              labelLine={false}
              label={renderCustomLabel}
              outerRadius="82%"
              innerRadius="50%"
              paddingAngle={2}
              dataKey="value"
            >
              {chartData.map((entry, index) => (
                <Cell
                  key={`cell-${index}`}
                  fill={sliceColor(index)}
                  stroke="#ffffff"
                  strokeWidth={2}
                />
              ))}
            </Pie>
            <Tooltip
              contentStyle={tooltipContentStyle}
              formatter={(value, name, props) => {
                const item = props.payload
                return [
                  <div key="tooltip" className="text-sm space-y-0.5">
                    <div className="font-semibold text-ink">{item.name}</div>
                    <div className="text-ink">{item.value} runs ({((item.value / totalRuns) * 100).toFixed(1)}%)</div>
                    <div className="text-ink-muted">{item.km.toFixed(1)} km total</div>
                    {item.isSpecialEvents && item.includedTypes && (
                      <div className="text-ink-muted text-xs mt-1 pt-1 border-t border-border">
                        Includes: {item.includedTypes.join(', ')}
                      </div>
                    )}
                  </div>
                ]
              }}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>

      {/* Direct, restrained legend: a small swatch + label, no boxes. */}
      <div className="mt-4 flex flex-wrap gap-x-4 gap-y-2 justify-center">
        {chartData.map((item, index) => (
          <div key={item.name} className="flex items-center gap-2">
            <span
              className="w-2.5 h-2.5 rounded-full flex-shrink-0"
              style={{ backgroundColor: sliceColor(index) }}
            />
            <span className="text-xs text-ink-muted">{item.name}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
