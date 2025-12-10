import { ComposedChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import { colors, runTypeColors } from '../../utils/theme'

const TOP_RUN_TYPES = ['Intervals', 'Soft Sand', 'River Loop', 'Lakes Loop', 'Social']
const ONE_MONTH_MS = 30 * 24 * 60 * 60 * 1000 // ~30 days in milliseconds

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

  // For each run type, find gaps > 1 month
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

  // Build chart data - one entry per unique date
  // For connecting lines, we need to track the "last known value" for each type
  // but insert undefined when there's a gap > 1 month
  const chartData = []
  const lastKnownTime = {}
  TOP_RUN_TYPES.forEach(type => { lastKnownTime[type] = null })

  allTimes.forEach(time => {
    const matchingRuns = sortedRuns.filter(r => r.parsedDate.getTime() === time)
    const firstMatch = matchingRuns[0]

    const point = {
      time,
      date: firstMatch.parsedDate.toLocaleDateString('en-AU', { day: 'numeric', month: 'short' }),
      fullDate: firstMatch.date
    }

    // Add attendance values for each run type that occurred at this time
    matchingRuns.forEach(run => {
      const type = run.runType
      // Check if there's a gap before this point for this type
      if (typeGaps[type].has(time)) {
        // We'll handle this by using a segment approach below
      }
      point[type] = run.totalAttendance
      lastKnownTime[type] = time
    })

    chartData.push(point)
  })

  // For gap handling with connectNulls, we need a different approach
  // Let's create segmented data keys: e.g., "Intervals_0", "Intervals_1" for different segments
  const segmentedData = []
  const currentSegment = {}
  TOP_RUN_TYPES.forEach(type => { currentSegment[type] = 0 })

  // Track which segment each data point belongs to per type
  const segmentTracker = {}
  TOP_RUN_TYPES.forEach(type => {
    segmentTracker[type] = []
    let segment = 0
    const typeRuns = runsByType[type]
    typeRuns.forEach((run, idx) => {
      if (typeGaps[type].has(run.time)) {
        segment++
      }
      segmentTracker[type].push({ time: run.time, segment, attendance: run.attendance })
    })
  })

  // Create month-based x-axis with even spacing (Jan-Dec)
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
  const year = sortedRuns.length > 0 ? sortedRuns[0].parsedDate.getFullYear() : 2025

  // Initialize with all 12 months
  months.forEach((month, idx) => {
    segmentedData.push({
      time: new Date(year, idx, 15).getTime(), // Mid-month for positioning
      date: month,
      fullDate: '',
      isMonthMarker: true
    })
  })

  // Add actual data points
  allTimes.forEach(time => {
    const matchingRuns = sortedRuns.filter(r => r.parsedDate.getTime() === time)
    const firstMatch = matchingRuns[0]

    const point = {
      time,
      date: '', // Don't show date labels for data points
      fullDate: firstMatch.date
    }

    // For each type, add the value with its segment key
    TOP_RUN_TYPES.forEach(type => {
      const tracker = segmentTracker[type].find(t => t.time === time)
      if (tracker) {
        point[`${type}_${tracker.segment}`] = tracker.attendance
        point[type] = tracker.attendance // Also keep original for tooltip
      }
    })

    segmentedData.push(point)
  })

  // Sort by time
  segmentedData.sort((a, b) => a.time - b.time)

  // Get max segment count per type
  const maxSegments = {}
  TOP_RUN_TYPES.forEach(type => {
    const segments = segmentTracker[type].map(t => t.segment)
    maxSegments[type] = segments.length > 0 ? Math.max(...segments) + 1 : 0
  })

  return (
    <div className="bg-white rounded-2xl shadow-md p-6">
      <h3 className="text-lg font-bold text-espresso mb-4">Attendance by Run Type</h3>

      <div className="h-72">
        <ResponsiveContainer width="100%" height="100%">
          <ComposedChart data={segmentedData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke={colors.latte} horizontal={true} vertical={false} />
            <XAxis
              dataKey="date"
              tick={{ fill: colors.roast, fontSize: 11 }}
              tickLine={false}
              axisLine={{ stroke: colors.latte }}
              interval={0}
              tickFormatter={(value) => value}
            />
            <YAxis
              tick={{ fill: colors.roast, fontSize: 12 }}
              tickLine={{ stroke: colors.latte }}
              axisLine={{ stroke: colors.latte }}
              allowDecimals={false}
            />
            {TOP_RUN_TYPES.flatMap(type =>
              Array.from({ length: maxSegments[type] }, (_, seg) => (
                <Line
                  key={`${type}_${seg}`}
                  type="monotone"
                  dataKey={`${type}_${seg}`}
                  name={`${type}_${seg}`}
                  stroke={runTypeColors[type] || colors.coffee}
                  strokeWidth={2}
                  dot={{ r: 3, fill: runTypeColors[type] || colors.coffee }}
                  connectNulls={true}
                  activeDot={{ r: 5 }}
                  legendType="none"
                />
              ))
            )}
          </ComposedChart>
        </ResponsiveContainer>
      </div>

      {/* Custom Legend */}
      <div className="mt-4 flex flex-wrap justify-center gap-4 text-sm">
        {TOP_RUN_TYPES.map(type => (
          <div key={type} className="flex items-center gap-1.5">
            <div
              className="w-4 h-0.5 rounded"
              style={{ backgroundColor: runTypeColors[type] || colors.coffee }}
            />
            <span className="text-roast">{type}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
