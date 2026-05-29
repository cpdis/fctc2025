import { useState, useEffect } from 'react'
import { ComposedChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LabelList } from 'recharts'
import {
  palette,
  axisProps,
  gridProps,
  tooltipContentStyle,
  tooltipLabelStyle,
  tooltipItemStyle,
  tooltipCursor,
} from '../../utils/chartConfig'

const TOP_RUN_TYPES = ['Intervals', 'Soft Sand', 'River Loop', 'Lakes Loop', 'Social']
const ONE_MONTH_MS = 30 * 24 * 60 * 60 * 1000 // ~30 days in milliseconds

// One stable color per run type, drawn from the restrained data palette. Order
// follows TOP_RUN_TYPES so the primary series (Intervals) gets the ink, and the
// rest recede through the accent + greys.
const TYPE_COLOR = Object.fromEntries(
  TOP_RUN_TYPES.map((type, i) => [type, palette[i % palette.length]])
)

// Tracks whether we're on a narrow (mobile) viewport. On mobile the direct
// end-labels are dropped (they overlap and steal horizontal room from an
// already-cramped plot); a compact swatch legend stands in for them instead.
function useIsMobile(query = '(max-width: 640px)') {
  const [isMobile, setIsMobile] = useState(false)
  useEffect(() => {
    const mq = window.matchMedia(query)
    const update = () => setIsMobile(mq.matches)
    update()
    mq.addEventListener('change', update)
    return () => mq.removeEventListener('change', update)
  }, [query])
  return isMobile
}

export default function AttendanceChart({ runs }) {
  const isMobile = useIsMobile()

  // Filter and sort runs
  const sortedRuns = runs
    .filter(run => run.parsedDate && TOP_RUN_TYPES.includes(run.runType))
    .sort((a, b) => a.parsedDate.getTime() - b.parsedDate.getTime())

  // Group runs by type
  const runsByType = {}
  TOP_RUN_TYPES.forEach(type => { runsByType[type] = [] })
  sortedRuns.forEach(run => {
    runsByType[run.runType].push({
      time: run.parsedDate.getTime(),
      attendance: run.totalAttendance,
      date: run.parsedDate.toLocaleDateString('en-AU', { day: 'numeric', month: 'short' }),
      fullDate: run.date
    })
  })

  // Create unified timeline with all dates
  const allTimes = [...new Set(sortedRuns.map(r => r.parsedDate.getTime()))].sort((a, b) => a - b)

  // For each run type, find gaps > 1 month. A line should NOT connect across a
  // long absence, so we break each type's series into separate segments at those
  // gaps and render one <Line> per segment. (connectNulls then only bridges the
  // intervening dates belonging to OTHER types within the same segment.)
  const typeGaps = {}
  TOP_RUN_TYPES.forEach(type => {
    typeGaps[type] = new Set()
    const typeRuns = runsByType[type]
    for (let i = 1; i < typeRuns.length; i++) {
      if (typeRuns[i].time - typeRuns[i - 1].time > ONE_MONTH_MS) {
        typeGaps[type].add(typeRuns[i].time)
      }
    }
  })

  // Assign each of a type's runs to a segment index (bumped at every gap).
  const segmentTracker = {}
  TOP_RUN_TYPES.forEach(type => {
    segmentTracker[type] = []
    let segment = 0
    runsByType[type].forEach((run) => {
      if (typeGaps[type].has(run.time)) {
        segment++
      }
      segmentTracker[type].push({ time: run.time, segment, attendance: run.attendance })
    })
  })

  // Plot on a real time axis (x = run timestamp). This places points at their
  // true calendar position, so the tooltip cursor maps to the right run and the
  // month ticks land where they belong, instead of the old empty-string category
  // axis (which collapsed every data point to the same slot and mislabeled the
  // tooltip). One row per run date carrying the segmented attendance keys.
  const segmentedData = allTimes.map((time) => {
    const matchingRuns = sortedRuns.filter((r) => r.parsedDate.getTime() === time)
    const point = { time, fullDate: matchingRuns[0].date }
    TOP_RUN_TYPES.forEach((type) => {
      const tracker = segmentTracker[type].find((t) => t.time === time)
      if (tracker) {
        point[`${type}_${tracker.segment}`] = tracker.attendance
        point[type] = tracker.attendance // un-segmented key, read by the tooltip
      }
    })
    return point
  })
  // allTimes is already sorted ascending, so segmentedData is too.

  // Evenly spaced month ticks across the data range, clamped so the first tick
  // sits at the first run rather than before the domain.
  const firstT = segmentedData.length ? segmentedData[0].time : 0
  const lastT = segmentedData.length ? segmentedData[segmentedData.length - 1].time : 0
  const monthTicks = []
  if (segmentedData.length) {
    const cursor = new Date(firstT)
    cursor.setDate(1)
    while (cursor.getTime() <= lastT) {
      monthTicks.push(Math.max(cursor.getTime(), firstT))
      cursor.setMonth(cursor.getMonth() + 1)
    }
  }
  const fmtMonth = (t) => new Date(t).toLocaleDateString('en-AU', { month: 'short' })

  // Number of segments per type, and the index of each type's LAST segment so we
  // can hang a single direct end-label on it (no boxed legend needed).
  const maxSegments = {}
  TOP_RUN_TYPES.forEach(type => {
    const segments = segmentTracker[type].map(t => t.segment)
    maxSegments[type] = segments.length > 0 ? Math.max(...segments) + 1 : 0
  })

  // Custom tooltip: the default one mislabels these segmented multi-line series
  // (it would surface whichever series matched first). Read the hovered row
  // directly and show only the run type(s) that actually occurred on that date,
  // each with its line color.
  const renderTooltip = ({ active, payload }) => {
    if (!active || !payload?.length) return null
    const row = payload[0].payload
    const items = TOP_RUN_TYPES.filter((t) => row[t] != null)
    if (!items.length) return null
    return (
      <div style={tooltipContentStyle}>
        {row.fullDate && <div style={tooltipLabelStyle}>{row.fullDate}</div>}
        {items.map((t) => (
          <div key={t} style={{ ...tooltipItemStyle, display: 'flex', alignItems: 'center', gap: 6 }}>
            <span
              style={{
                width: 8,
                height: 8,
                borderRadius: 9999,
                background: TYPE_COLOR[t],
                flex: '0 0 auto',
              }}
            />
            {t}: {row[t]}
          </div>
        ))}
      </div>
    )
  }

  // Direct label renderer: prints the run-type name at the rightmost point of a
  // line (its final, non-null value), in the line's color. Tufte: label the data
  // directly instead of forcing the eye to a legend and back.
  const endLabel = (type) => (props) => {
    const { x, y, index, value } = props
    if (value == null) return null
    // Only draw on the very last data row that has a value for this segment key.
    const key = props.dataKey
    let lastIdx = -1
    segmentedData.forEach((row, i) => {
      if (row[key] != null) lastIdx = i
    })
    if (index !== lastIdx) return null
    return (
      <text
        x={x + 6}
        y={y}
        fill={TYPE_COLOR[type]}
        fontSize={11}
        fontWeight={600}
        dominantBaseline="central"
        fontFamily="var(--font-sans)"
      >
        {type}
      </text>
    )
  }

  // Run types that actually appear in the data — drives the mobile legend so we
  // don't list series that were never plotted.
  const presentTypes = TOP_RUN_TYPES.filter((type) => runsByType[type].length > 0)

  return (
    <div className="card-clean p-6">
      <h3 className="font-display text-lg font-semibold text-ink mb-4">Attendance by Run Type</h3>

      <div className="h-80 sm:h-72">
        <ResponsiveContainer width="100%" height="100%">
          {/* On mobile the direct end-labels are dropped, so the plot can use the
              full width (tight right margin); on larger screens the extra right
              margin leaves room for the labels hung off each line's last point. */}
          <ComposedChart data={segmentedData} margin={{ top: 12, right: isMobile ? 8 : 64, left: 0, bottom: 4 }}>
            <CartesianGrid {...gridProps} />
            <XAxis
              {...axisProps}
              dataKey="time"
              type="number"
              scale="time"
              domain={[firstT, lastT]}
              ticks={monthTicks}
              tickFormatter={fmtMonth}
            />
            <YAxis allowDecimals={false} width={32} {...axisProps} />
            <Tooltip content={renderTooltip} cursor={tooltipCursor} />
            {TOP_RUN_TYPES.flatMap(type =>
              Array.from({ length: maxSegments[type] }, (_, seg) => {
                const isLastSegment = seg === maxSegments[type] - 1
                return (
                  <Line
                    key={`${type}_${seg}`}
                    type="monotone"
                    dataKey={`${type}_${seg}`}
                    name={type}
                    stroke={TYPE_COLOR[type]}
                    strokeWidth={2}
                    strokeLinecap="round"
                    dot={{ r: 3, fill: TYPE_COLOR[type], strokeWidth: 0 }}
                    connectNulls={true}
                    activeDot={{ r: 5, strokeWidth: 2, stroke: '#fff', fill: TYPE_COLOR[type] }}
                    legendType="none"
                  >
                    {isLastSegment && !isMobile && (
                      <LabelList dataKey={`${type}_${seg}`} content={endLabel(type)} />
                    )}
                  </Line>
                )
              })
            )}
          </ComposedChart>
        </ResponsiveContainer>
      </div>

      {/* Mobile legend: stands in for the direct end-labels, which are dropped on
          narrow screens. Only the run types present in the data are listed. */}
      {isMobile && presentTypes.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1.5">
          {presentTypes.map((type) => (
            <span key={type} className="flex items-center gap-1.5 text-xs text-ink-muted">
              <span
                className="inline-block h-2 w-2 rounded-full"
                style={{ background: TYPE_COLOR[type] }}
              />
              {type}
            </span>
          ))}
        </div>
      )}
    </div>
  )
}
