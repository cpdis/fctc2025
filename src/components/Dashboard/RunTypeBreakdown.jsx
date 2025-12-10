import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts'
import { runTypeColors, colors, getRunTypeDisplayName } from '../../utils/theme'

// Number of top run types to show individually (rest become "Special Events")
const TOP_TYPES_COUNT = 6

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
    if (percent < 0.05) return null // Don't show labels for small slices

    const RADIAN = Math.PI / 180
    const radius = innerRadius + (outerRadius - innerRadius) * 0.5
    const x = cx + radius * Math.cos(-midAngle * RADIAN)
    const y = cy + radius * Math.sin(-midAngle * RADIAN)

    return (
      <text
        x={x}
        y={y}
        fill="white"
        textAnchor="middle"
        dominantBaseline="central"
        fontSize={11}
        fontWeight="600"
        fontFamily="DM Sans"
        style={{ textShadow: '0 1px 2px rgba(0,0,0,0.3)' }}
      >
        {`${(percent * 100).toFixed(0)}%`}
      </text>
    )
  }

  return (
    <div
      className="bg-white rounded-2xl p-6 relative overflow-hidden"
      style={{
        boxShadow: `
          0 1px 2px rgba(2, 9, 18, 0.04),
          0 4px 12px rgba(2, 9, 18, 0.06)
        `
      }}
    >
      {/* Subtle accent line */}
      <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-pink via-mint to-terracotta opacity-50" />

      <h3 className="font-display text-lg font-bold text-espresso mb-4">Run Type Distribution</h3>

      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={chartData}
              cx="50%"
              cy="50%"
              labelLine={false}
              label={renderCustomLabel}
              outerRadius={100}
              innerRadius={45}
              paddingAngle={3}
              dataKey="value"
            >
              {chartData.map((entry, index) => (
                <Cell
                  key={`cell-${index}`}
                  fill={runTypeColors[entry.rawName] || runTypeColors[entry.name] || colors.coffee}
                  stroke="#fff"
                  strokeWidth={3}
                  style={{
                    filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.1))'
                  }}
                />
              ))}
            </Pie>
            <Tooltip
              contentStyle={{
                backgroundColor: '#fff',
                border: 'none',
                borderRadius: '12px',
                boxShadow: '0 4px 20px rgba(2, 9, 18, 0.12)',
                padding: '12px 16px'
              }}
              formatter={(value, name, props) => {
                const item = props.payload
                return [
                  <div key="tooltip" className="text-sm space-y-1">
                    <div className="font-display font-bold text-espresso">{item.name}</div>
                    <div className="font-medium">{item.value} runs ({((item.value / totalRuns) * 100).toFixed(1)}%)</div>
                    <div className="text-coffee/70">{item.km.toFixed(1)} km total</div>
                    {item.isSpecialEvents && item.includedTypes && (
                      <div className="text-coffee/50 text-xs mt-1 pt-1 border-t border-cream">
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

      {/* Legend - warmer styling */}
      <div className="mt-4 flex flex-wrap gap-3 justify-center">
        {chartData.slice(0, 6).map((item) => (
          <div
            key={item.name}
            className="flex items-center gap-2 px-2 py-1 rounded-lg hover:bg-cream/50 transition-colors cursor-default"
          >
            <span
              className="w-3 h-3 rounded-full"
              style={{
                backgroundColor: runTypeColors[item.rawName] || runTypeColors[item.name] || colors.coffee,
                boxShadow: `0 0 0 2px ${(runTypeColors[item.rawName] || runTypeColors[item.name] || colors.coffee)}20`
              }}
            />
            <span className="text-xs text-roast font-medium">{item.name}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
