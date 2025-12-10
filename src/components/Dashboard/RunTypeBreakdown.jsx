import { PieChart, Pie, Cell, ResponsiveContainer, Legend, Tooltip } from 'recharts'
import { runTypeColors, colors } from '../../utils/theme'

export default function RunTypeBreakdown({ runsByType }) {
  const chartData = Object.entries(runsByType)
    .map(([type, stats]) => ({
      name: type,
      value: stats.count,
      km: stats.totalKm,
      attendance: stats.totalAttendance
    }))
    .sort((a, b) => b.value - a.value)

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
        fontSize={12}
        fontWeight="bold"
      >
        {`${(percent * 100).toFixed(0)}%`}
      </text>
    )
  }

  return (
    <div className="bg-white rounded-2xl shadow-md p-6">
      <h3 className="text-lg font-bold text-espresso mb-4">Run Type Distribution</h3>

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
              innerRadius={40}
              paddingAngle={2}
              dataKey="value"
            >
              {chartData.map((entry, index) => (
                <Cell
                  key={`cell-${index}`}
                  fill={runTypeColors[entry.name] || colors.coffee}
                  stroke={colors.cream}
                  strokeWidth={2}
                />
              ))}
            </Pie>
            <Tooltip
              contentStyle={{
                backgroundColor: colors.cream,
                border: `1px solid ${colors.latte}`,
                borderRadius: '8px',
                boxShadow: '0 4px 6px -1px rgb(0 0 0 / 0.1)'
              }}
              formatter={(value, name, props) => {
                const item = props.payload
                return [
                  <div key="tooltip" className="text-sm">
                    <div className="font-bold">{item.name}</div>
                    <div>{item.value} runs ({((item.value / totalRuns) * 100).toFixed(1)}%)</div>
                    <div>{item.km.toFixed(1)} km total</div>
                  </div>
                ]
              }}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>

      {/* Legend */}
      <div className="mt-4 flex flex-wrap gap-2 justify-center">
        {chartData.slice(0, 6).map((item) => (
          <div key={item.name} className="flex items-center gap-1.5 text-xs">
            <span
              className="w-3 h-3 rounded-full"
              style={{ backgroundColor: runTypeColors[item.name] || colors.coffee }}
            />
            <span className="text-coffee">{item.name}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
