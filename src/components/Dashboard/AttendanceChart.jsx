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

export default function AttendanceChart({ runs }) {
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

  // Build chart rows: 12 evenly-spaced month markers (for the x-axis) plus one
  // row per actual run date carrying segmented attendance keys.
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
  const year = sortedRuns.length > 0 ? sortedRuns[0].parsedDate.getFullYear() : 2025

  const segmentedData = []
  months.forEach((month, idx) => {
    segmentedData.push({
      time: new Date(year, idx, 15).getTime(), // Mid-month for positioning
      date: month,
      fullDate: '',
      isMonthMarker: true
    })
  })

  allTimes.forEach(time => {
    const matchingRuns = sortedRuns.filter(r => r.parsedDate.getTime() === time)
    const firstMatch = matchingRuns[0]

    const point = {
      time,
      date: '', // Don't show date labels for data points (months mark the axis)
      fullDate: firstMatch.date
    }

    TOP_RUN_TYPES.forEach(type => {
      const tracker = segmentTracker[type].find(t => t.time === time)
      if (tracker) {
        point[`${type}_${tracker.segment}`] = tracker.attendance
        point[type] = tracker.attendance // Also keep original key for tooltip
      }
    })

    segmentedData.push(point)
  })

  segmentedData.sort((a, b) => a.time - b.time)

  // Number of segments per type, and the index of each type's LAST segment so we
  // can hang a single direct end-label on it (no boxed legend needed).
  const maxSegments = {}
  TOP_RUN_TYPES.forEach(type => {
    const segments = segmentTracker[type].map(t => t.segment)
    maxSegments[type] = segments.length > 0 ? Math.max(...segments) + 1 : 0
  })

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

  return (
    <div className="card-clean p-6">
      <h3 className="font-display text-lg font-semibold text-ink mb-4">Attendance by Run Type</h3>

      <div className="h-72">
        <ResponsiveContainer width="100%" height="100%">
          {/* Extra right margin leaves room for the direct end-labels. */}
          <ComposedChart data={segmentedData} margin={{ top: 12, right: 64, left: 0, bottom: 4 }}>
            <CartesianGrid {...gridProps} />
            <XAxis dataKey="date" interval={0} {...axisProps} />
            <YAxis allowDecimals={false} {...axisProps} />
            <Tooltip
              contentStyle={tooltipContentStyle}
              labelStyle={tooltipLabelStyle}
              itemStyle={tooltipItemStyle}
              cursor={tooltipCursor}
            />
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
                    {isLastSegment && (
                      <LabelList dataKey={`${type}_${seg}`} content={endLabel(type)} />
                    )}
                  </Line>
                )
              })
            )}
          </ComposedChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}
