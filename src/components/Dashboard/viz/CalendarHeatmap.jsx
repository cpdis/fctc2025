import { ActivityCalendar } from 'react-activity-calendar'
import { dashboardColors } from '../../../utils/theme'
import { runFrequencyByDate } from '../../../utils/dashboardMetrics'

/**
 * CalendarHeatmap — GitHub-style run-frequency heatmap.
 *
 * Each cell is a calendar day; its shade encodes total attendance that day
 * (`runFrequencyByDate`). We bucket the nonzero counts into 4 levels using their
 * quartiles so the ramp adapts to the season's actual range instead of arbitrary
 * fixed thresholds. The ramp is monochrome greys lifting to the dashboard accent
 * (NOT the library's default GitHub green) to stay native to the clean theme.
 *
 * Honesty: the metric only emits real run days, but the calendar needs a full
 * date range so empty days render as level 0. We fill the year (Jan 1..Dec 31 of
 * the season, clamped to "today" if the season is the current partial year) with
 * level-0 days and overlay the real counts on top. No fabricated attendance.
 */

// Quartile thresholds over the nonzero counts. Returns up to 3 cut points that
// split values into 4 buckets (levels 1..4). Level 0 is reserved for zero days.
export function quartileThresholds(counts) {
  const nonzero = counts.filter((c) => c > 0).sort((a, b) => a - b)
  if (nonzero.length === 0) return [1, 2, 3]
  const q = (p) => {
    const idx = (nonzero.length - 1) * p
    const lo = Math.floor(idx)
    const hi = Math.ceil(idx)
    if (lo === hi) return nonzero[lo]
    return nonzero[lo] + (nonzero[hi] - nonzero[lo]) * (idx - lo)
  }
  return [q(0.25), q(0.5), q(0.75)]
}

// Bucket a single count into a 0..4 level given quartile cut points.
export function levelForCount(count, thresholds) {
  if (count <= 0) return 0
  if (count <= thresholds[0]) return 1
  if (count <= thresholds[1]) return 2
  if (count <= thresholds[2]) return 3
  return 4
}

// Local YYYY-MM-DD for a Date (no UTC shift). Mirrors the metric's keying.
function dateKey(d) {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/**
 * Build the full-year activity dataset the calendar library expects:
 *   [{ date: 'YYYY-MM-DD', count, level }]  — one entry per day of the season.
 *
 * @param {Array<{date,count}>} frequency  output of runFrequencyByDate
 * @param {number} year                     season year (for the date range)
 * @param {Date}   [today]                  upper clamp for partial/current years
 */
export function buildCalendarData(frequency, year, today = new Date()) {
  const byDay = new Map(frequency.map((d) => [d.date, d.count]))
  const thresholds = quartileThresholds(frequency.map((d) => d.count))

  const start = new Date(year, 0, 1)
  // End at Dec 31, or today if we're partway through the current year (so we
  // don't render a bunch of empty future cells for a partial season).
  let end = new Date(year, 11, 31)
  if (today.getFullYear() === year && today < end) end = today

  const out = []
  const cursor = new Date(start)
  while (cursor <= end) {
    const key = dateKey(cursor)
    const count = byDay.get(key) ?? 0
    out.push({ date: key, count, level: levelForCount(count, thresholds) })
    cursor.setDate(cursor.getDate() + 1)
  }
  return out
}

// Monochrome → accent ramp (5 stops, level 0..4). Empty days are the card-grey
// border tone; busier days lift toward the dark ink accent.
const COLOR_SCALE = ['#ededea', '#cfcfc9', '#a8a8a2', '#5a5a55', dashboardColors.ink]

export default function CalendarHeatmap({ data, year }) {
  const frequency = runFrequencyByDate(data?.runs ?? [])
  const resolvedYear =
    year ?? (frequency.length ? Number(frequency[0].date.slice(0, 4)) : new Date().getFullYear())
  const calendarData = buildCalendarData(frequency, resolvedYear)

  const totalAttendance = frequency.reduce((s, d) => s + d.count, 0)

  return (
    <div className="card-clean p-6">
      <div className="flex items-baseline justify-between mb-4">
        <h3 className="font-display text-lg font-semibold text-ink">Run Calendar</h3>
        <span className="text-sm text-ink-muted">daily attendance, {resolvedYear}</span>
      </div>

      {frequency.length === 0 ? (
        <p className="text-sm text-ink-muted">No runs recorded yet this season.</p>
      ) : (
        // Horizontal scroll on narrow screens so the year never squashes.
        <div className="overflow-x-auto">
          <ActivityCalendar
            data={calendarData}
            theme={{ light: COLOR_SCALE, dark: COLOR_SCALE }}
            colorScheme="light"
            blockSize={12}
            blockMargin={3}
            fontSize={12}
            maxLevel={4}
            labels={{
              totalCount: `${totalAttendance.toLocaleString()} total attendances in ${resolvedYear}`,
            }}
            aria-label={`Run frequency calendar for ${resolvedYear}`}
            hideTotalCount={false}
          />
        </div>
      )}
    </div>
  )
}
