import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  LabelList,
} from 'recharts'
import {
  palette,
  axisProps,
  gridProps,
  tooltipContentStyle,
  tooltipLabelStyle,
  tooltipItemStyle,
  tooltipCursor,
} from '../../../utils/chartConfig'
import { cumulativeSeries } from '../../../utils/dashboardMetrics'

/**
 * SeasonProgress — cumulative season-distance line.
 *
 * One point per dated run, accumulating member-kilometres across the season so
 * the curve's endpoint reconciles with the "Aggregate Distance" headline stat
 * (both are actualKm summed over each member's attended runs). For a partial
 * season (e.g. 2026) the line simply stops at the latest run; we never project
 * forward, so the curve reads as "where the club is right now".
 *
 * Tufte choices: a single restrained ink series, a soft fill to give the curve
 * weight, faint dotted horizontal grid only, no chartjunk, and a direct value
 * label printed at the line's end (no boxed legend).
 *
 * @param {Object} data - full parseRunData output (uses data.runs)
 */
export default function SeasonProgress({ data }) {
  const series = cumulativeSeries(data?.runs ?? [])

  // Plot against real time (not run index) so the curve's horizontal spacing
  // reflects the calendar: a dense run week takes proportionally more width than
  // a quiet one. Each row carries its timestamp; we keep every real run (no
  // fabricated dates).
  const rows = series.map((p) => ({
    t: p.parsedDate.getTime(),
    fullDate: p.date,
    km: Math.round(p.cumulativePersonKm),
  }))

  const lastIndex = rows.length - 1
  const finalKm = lastIndex >= 0 ? rows[lastIndex].km : 0

  // Evenly spaced month ticks across the data range, so labels read "Jan, Feb,
  // ..." instead of clustering on whichever run dates happen to fall there.
  const firstT = rows.length ? rows[0].t : 0
  const lastT = rows.length ? rows[lastIndex].t : 0
  const monthTicks = []
  if (rows.length) {
    const cursor = new Date(firstT)
    cursor.setDate(1)
    while (cursor.getTime() <= lastT) {
      monthTicks.push(Math.max(cursor.getTime(), firstT))
      cursor.setMonth(cursor.getMonth() + 1)
    }
  }
  const fmtMonth = (t) => new Date(t).toLocaleDateString('en-AU', { month: 'short' })

  // Direct end-label: print the running total at the rightmost point only.
  const endLabel = (props) => {
    const { x, y, index } = props
    if (index !== lastIndex) return null
    return (
      <text
        x={x - 6}
        y={y - 10}
        fill={palette[0]}
        fontSize={12}
        fontWeight={600}
        textAnchor="end"
        fontFamily="var(--font-sans)"
      >
        {finalKm.toLocaleString()} km
      </text>
    )
  }

  return (
    <div className="card-clean p-6">
      <div className="flex items-baseline justify-between mb-4">
        <h3 className="font-display text-lg font-semibold text-ink">Season Progress</h3>
        <span className="text-sm text-ink-muted">cumulative distance</span>
      </div>

      {rows.length === 0 ? (
        <p className="text-sm text-ink-muted">No dated runs yet this season.</p>
      ) : (
        <div className="h-64">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart
              data={rows}
              margin={{ top: 16, right: 20, left: 0, bottom: 4 }}
              aria-label={`Cumulative season distance, ${finalKm} km total`}
            >
              <defs>
                <linearGradient id="seasonProgressFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={palette[0]} stopOpacity={0.12} />
                  <stop offset="100%" stopColor={palette[0]} stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid {...gridProps} />
              <XAxis
                {...axisProps}
                dataKey="t"
                type="number"
                scale="time"
                domain={[firstT, lastT]}
                ticks={monthTicks}
                tickFormatter={fmtMonth}
              />
              <YAxis
                allowDecimals={false}
                width={40}
                tickFormatter={(v) => (v >= 1000 ? `${v / 1000}k` : `${v}`)}
                {...axisProps}
              />
              <Tooltip
                contentStyle={tooltipContentStyle}
                labelStyle={tooltipLabelStyle}
                itemStyle={tooltipItemStyle}
                cursor={tooltipCursor}
                formatter={(value) => [`${value.toLocaleString()} km`, 'Cumulative']}
                labelFormatter={(_, p) => p?.[0]?.payload?.fullDate ?? ''}
              />
              <Area
                type="monotone"
                dataKey="km"
                stroke={palette[0]}
                strokeWidth={2}
                fill="url(#seasonProgressFill)"
                dot={false}
                activeDot={{ r: 4, fill: palette[0] }}
                isAnimationActive={false}
              >
                <LabelList dataKey="km" content={endLabel} />
              </Area>
            </AreaChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  )
}
