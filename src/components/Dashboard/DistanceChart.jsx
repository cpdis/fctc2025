import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from 'recharts'
import { colors, runTypeColors } from '../../utils/theme'

export default function DistanceChart({ data, filteredRuns }) {
  // Calculate count by run type from filtered runs
  const runsByType = {}
  filteredRuns.forEach(run => {
    const type = run.runType
    if (!runsByType[type]) {
      runsByType[type] = { type, totalKm: 0, count: 0 }
    }
    runsByType[type].totalKm += run.actualKm || 0
    runsByType[type].count++
  })

  // Sort by count and take top 5
  const chartData = Object.values(runsByType)
    .sort((a, b) => b.count - a.count)
    .slice(0, 5)

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
      <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-terracotta via-orange to-amber opacity-50" />

      <h3 className="font-display text-lg font-bold text-navy mb-4">Runs by Type</h3>

      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={chartData} layout="vertical" margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" stroke={colors.creamDark} horizontal={true} vertical={false} />
            <XAxis
              type="number"
              tick={{ fill: colors.roast, fontSize: 12, fontFamily: 'DM Sans' }}
              tickLine={{ stroke: colors.creamDark }}
              axisLine={{ stroke: colors.creamDark }}
              allowDecimals={false}
            />
            <YAxis
              dataKey="type"
              type="category"
              tick={{ fill: colors.roast, fontSize: 12, fontFamily: 'DM Sans', fontWeight: 500 }}
              tickLine={false}
              axisLine={{ stroke: colors.creamDark }}
              width={90}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: '#fff',
                border: 'none',
                borderRadius: '12px',
                boxShadow: '0 4px 20px rgba(2, 9, 18, 0.12)',
                padding: '12px 16px'
              }}
              labelStyle={{ color: colors.espresso, fontWeight: 'bold', fontFamily: 'Bricolage Grotesque' }}
              formatter={(value, name, props) => {
                const item = props.payload
                return [
                  <div key="tooltip" className="text-sm space-y-1">
                    <div className="font-medium">{item.count} runs</div>
                    <div className="text-coffee/70">{item.totalKm.toFixed(1)} km total</div>
                  </div>
                ]
              }}
              cursor={{ fill: 'rgba(212, 165, 116, 0.1)' }}
            />
            <Bar dataKey="count" radius={[0, 8, 8, 0]} barSize={28}>
              {chartData.map((entry, index) => (
                <Cell
                  key={`cell-${index}`}
                  fill={runTypeColors[entry.type] || colors.coffee}
                  style={{
                    filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.1))'
                  }}
                />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>

      <div className="mt-4 text-sm text-coffee/60 text-center font-medium">
        Number of runs per type
      </div>
    </div>
  )
}
