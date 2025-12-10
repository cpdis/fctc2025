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
    <div className="bg-white rounded-2xl shadow-md p-6">
      <h3 className="text-lg font-bold text-navy mb-4">Runs by Type</h3>

      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={chartData} layout="vertical" margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" stroke={colors.latte} horizontal={true} vertical={false} />
            <XAxis
              type="number"
              tick={{ fill: colors.roast, fontSize: 12 }}
              tickLine={{ stroke: colors.latte }}
              axisLine={{ stroke: colors.latte }}
              allowDecimals={false}
            />
            <YAxis
              dataKey="type"
              type="category"
              tick={{ fill: colors.roast, fontSize: 12 }}
              tickLine={false}
              axisLine={{ stroke: colors.latte }}
              width={90}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: colors.cream,
                border: `1px solid ${colors.latte}`,
                borderRadius: '8px',
                boxShadow: '0 4px 6px -1px rgb(0 0 0 / 0.1)'
              }}
              labelStyle={{ color: colors.espresso, fontWeight: 'bold' }}
              formatter={(value, name, props) => {
                const item = props.payload
                return [
                  <div key="tooltip" className="text-sm">
                    <div>{item.count} runs</div>
                    <div>{item.totalKm.toFixed(1)} km total</div>
                  </div>
                ]
              }}
            />
            <Bar dataKey="count" radius={[0, 4, 4, 0]}>
              {chartData.map((entry, index) => (
                <Cell
                  key={`cell-${index}`}
                  fill={runTypeColors[entry.type] || colors.coffee}
                />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>

      <div className="mt-4 text-sm text-coffee text-center">
        Number of runs per type
      </div>
    </div>
  )
}
