/**
 * Dashboard trend metrics.
 *
 * Pure, side-effect-free derivations over the output of
 * `parseRunData(csvText, year)` (see ./dataParser.js). These feed a set of
 * Tufte-style visualizations (cumulative line, per-member sparklines,
 * small-multiples, slopegraph, calendar heatmap, bump chart). Rendering lives
 * elsewhere; this file is only the data layer.
 *
 * Honesty rules baked in here:
 *  - Partial seasons (e.g. 2026 runs only span ~5 months) must never fabricate
 *    points. Date-keyed series only contain real run dates. Monthly arrays
 *    follow `monthAxis` (first to latest run month), so months that have not
 *    happened yet never appear as zeros.
 *  - Members who attended nothing are excluded from per-member outputs.
 *  - `firstVsSecondHalf` splits at the TRUE data midpoint (earliest..latest run
 *    date), never a hardcoded month.
 */
import { isoDate } from './runLabels.js'

/**
 * Sort runs chronologically by parsedDate. Runs without a parsedDate are
 * dropped from date-ordered series (we can't honestly place them on a timeline).
 * Returns a new array; does not mutate the input.
 */
function datedRunsSorted(runs) {
  return (runs ?? [])
    .filter((r) => r && r.parsedDate instanceof Date && !Number.isNaN(r.parsedDate.getTime()))
    .slice()
    .sort((a, b) => a.parsedDate - b.parsedDate)
}

/** Local YYYY-MM key for a Date. */
function monthKey(d) {
  return isoDate(d).slice(0, 7)
}

/**
 * monthAxis(runs)
 *
 * @param {Array} runs - data.runs from parseRunData
 * @returns {Array<{ key: string, year: number, month: number }>}
 *
 * Every calendar month from the first dated run to the last, inclusive, keyed
 * YYYY-MM (month is 0-based). Month-bucketed series align to this axis:
 *
 *   2026 (partial)   Jan ... Sep            stops at the latest run month
 *   2025 (complete)  Jan ... Dec
 *   All time         Jan 2025 ... Sep 2026  seasons stay apart
 *
 * A fixed Jan..Dec array would draw months that have not happened yet as zero
 * attendance, and would fold 2025 and 2026 into the same twelve buckets.
 */
export function monthAxis(runs) {
  const sorted = datedRunsSorted(runs)
  if (sorted.length === 0) return []
  const last = sorted[sorted.length - 1].parsedDate
  const cursor = new Date(sorted[0].parsedDate.getFullYear(), sorted[0].parsedDate.getMonth(), 1)
  const axis = []
  while (cursor <= last) {
    axis.push({ key: monthKey(cursor), year: cursor.getFullYear(), month: cursor.getMonth() })
    cursor.setMonth(cursor.getMonth() + 1)
  }
  return axis
}

const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

/**
 * monthAxisLabel(axis)
 *
 * Human label for a month axis: "Jan–Sep 2026" inside one year,
 * "Jan 2025–Sep 2026" across years, "" when empty. Fixed English month names
 * so the label does not depend on the viewer's locale.
 */
export function monthAxisLabel(axis) {
  if (!axis?.length) return ''
  const first = axis[0]
  const last = axis[axis.length - 1]
  const name = (m) => MONTH_NAMES[m.month]
  if (first.key === last.key) return `${name(first)} ${first.year}`
  if (first.year === last.year) return `${name(first)}–${name(last)} ${last.year}`
  return `${name(first)} ${first.year}–${name(last)} ${last.year}`
}

/** Map each axis month key to its index, for O(1) bucketing. */
function monthIndex(axis) {
  return new Map(axis.map((m, i) => [m.key, i]))
}

/**
 * cumulativeSeries(runs)
 *
 * @param {Array} runs - data.runs from parseRunData
 * @returns {Array<{ date: string, parsedDate: Date, cumulativeKm: number,
 *                    cumulativePersonKm: number, cumulativeAttendance: number,
 *                    cumulativeRuns: number }>}
 *
 * One point per dated run, sorted ascending by date. Each point accumulates:
 *  - cumulativeKm: route distance (each run's actualKm counted once)
 *  - cumulativePersonKm: member-kilometres (actualKm x attending members). This
 *    reconciles exactly to data.totalClubKm (the "Aggregate Distance" headline),
 *    since both sum actualKm over each member's attended runs. Guests (+1's) are
 *    excluded so it matches the member-only headline, not aggregateKm.
 *  - cumulativeAttendance: total attendance incl. guests
 *  - cumulativeRuns: 1-per-run counter
 * Powers the season-progress line. Empty / degenerate input returns []. Multiple
 * runs on the same calendar day each get their own point.
 */
export function cumulativeSeries(runs) {
  const sorted = datedRunsSorted(runs)
  let km = 0
  let personKm = 0
  let attendance = 0
  let count = 0
  return sorted.map((run) => {
    km += run.actualKm || 0
    personKm += (run.actualKm || 0) * (run.attendees?.length || 0)
    attendance += run.totalAttendance || 0
    count += 1
    return {
      date: run.date,
      parsedDate: run.parsedDate,
      cumulativeKm: km,
      cumulativePersonKm: personKm,
      cumulativeAttendance: attendance,
      cumulativeRuns: count,
    }
  })
}

/**
 * Per-member current streak: consecutive most-recent runs (in chronological
 * order) that the member attended. Mirrors the convention in
 * calculations.js#calculateMemberStats (walk runs newest-first, stop at first
 * miss). We use the chronologically-sorted dated runs so the "most recent" end
 * is well-defined regardless of input ordering.
 */
function currentStreakFor(sortedRuns, member) {
  let streak = 0
  for (let i = sortedRuns.length - 1; i >= 0; i--) {
    if (sortedRuns[i].attendance?.[member]) streak++
    else break
  }
  return streak
}

/**
 * memberMonthlyAttendance(data)
 *
 * @param {Object} data - full parseRunData output
 * @returns {Array<{ name: string, totalRuns: number, totalKm: number,
 *                    monthly: number[], currentStreak: number }>}
 *
 * For each active member, attendance counts per month of `monthAxis(data.runs)`
 * (number of attended runs in that month). Sorted by totalRuns desc. Members
 * with zero attendance are excluded. Every `monthly` has the axis length (a
 * month the member skipped is 0) so a sparkline-per-member table aligns
 * vertically. Powers a sparkline table.
 */
export function memberMonthlyAttendance(data) {
  if (!data || !Array.isArray(data.members)) return []
  const sorted = datedRunsSorted(data.runs)
  const axis = monthAxis(sorted)
  const indexOf = monthIndex(axis)

  const rows = data.members.map((name) => {
    const monthly = new Array(axis.length).fill(0)
    let totalRuns = 0
    let totalKm = 0
    for (const run of sorted) {
      if (run.attendance?.[name]) {
        monthly[indexOf.get(monthKey(run.parsedDate))] += 1
        totalRuns += 1
        totalKm += run.actualKm || 0
      }
    }
    return {
      name,
      totalRuns,
      totalKm,
      monthly,
      currentStreak: currentStreakFor(sorted, name),
    }
  })

  return rows
    .filter((r) => r.totalRuns > 0)
    .sort((a, b) => b.totalRuns - a.totalRuns)
}

/**
 * runTypeMonthlyCounts(data)
 *
 * @param {Object} data - full parseRunData output
 * @returns {Array<{ type: string, monthly: number[], total: number }>}
 *
 * For each run type, run counts per month of `monthAxis(data.runs)` for
 * small-multiples. Sorted by total desc. Uses the run's raw `runType` string
 * (not the parser's normalized buckets) so every distinct type label gets its
 * own panel; change here if the dashboard prefers normalized buckets.
 */
export function runTypeMonthlyCounts(data) {
  if (!data) return []
  const sorted = datedRunsSorted(data.runs)
  const axis = monthAxis(sorted)
  const indexOf = monthIndex(axis)
  const byType = new Map()
  for (const run of sorted) {
    const type = run.runType || 'Other'
    if (!byType.has(type)) byType.set(type, new Array(axis.length).fill(0))
    byType.get(type)[indexOf.get(monthKey(run.parsedDate))] += 1
  }
  return Array.from(byType.entries())
    .map(([type, monthly]) => ({
      type,
      monthly,
      total: monthly.reduce((s, n) => s + n, 0),
    }))
    .sort((a, b) => b.total - a.total)
}

/**
 * firstVsSecondHalf(data)
 *
 * @param {Object} data - full parseRunData output
 * @returns {Array<{ name: string, first: number, second: number }>}
 *
 * Per active member, attendance counts split at the SEASON MIDPOINT. The
 * midpoint is the temporal midpoint of the actual data range:
 *   midpoint = earliestRunDate + (latestRunDate - earliestRunDate) / 2
 * computed from real run dates, NOT a hardcoded month. This matters for partial
 * seasons (2026 spans only ~5 months); a "June" split would be nonsense.
 *
 * Runs strictly before the midpoint go to `first`; runs on/after go to
 * `second`. Members with zero attendance are excluded. first + second equals
 * the member's total attended (dated) runs. Powers a slopegraph.
 */
export function firstVsSecondHalf(data) {
  if (!data || !Array.isArray(data.members)) return []
  const sorted = datedRunsSorted(data.runs)
  if (sorted.length === 0) return []

  const start = sorted[0].parsedDate.getTime()
  const end = sorted[sorted.length - 1].parsedDate.getTime()
  const midpoint = start + (end - start) / 2

  const rows = data.members.map((name) => {
    let first = 0
    let second = 0
    for (const run of sorted) {
      if (!run.attendance?.[name]) continue
      if (run.parsedDate.getTime() < midpoint) first += 1
      else second += 1
    }
    return { name, first, second }
  })

  return rows
    .filter((r) => r.first + r.second > 0)
    .sort((a, b) => b.first + b.second - (a.first + a.second))
}

/**
 * runFrequencyByDate(runs)
 *
 * @param {Array} runs - data.runs from parseRunData
 * @returns {Array<{ date: string, count: number }>}
 *
 * One entry per calendar day that had a run, keyed YYYY-MM-DD, for a calendar
 * heatmap. DESIGN CHOICE: `count` is total ATTENDANCE that day (sum of
 * totalAttendance across runs on that day), not the number of runs. Attendance
 * is the variable the heatmap is meant to show ("how busy was this day"), and
 * most days have exactly one run so a run-count heatmap would be near-binary.
 * Days with no run never appear (no fabricated zeros on a date-keyed series).
 * Sorted ascending by date. Only days with positive attendance are emitted.
 */
export function runFrequencyByDate(runs) {
  const sorted = datedRunsSorted(runs)
  const byDay = new Map()
  for (const run of sorted) {
    const key = isoDate(run.parsedDate)
    byDay.set(key, (byDay.get(key) || 0) + (run.totalAttendance || 0))
  }
  return Array.from(byDay.entries())
    .filter(([, count]) => count > 0)
    .map(([date, count]) => ({ date, count }))
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))
}

/**
 * rankByMonth(data)  [STRETCH]
 *
 * @param {Object} data - full parseRunData output
 * @returns {Array<{ name: string, ranks: Array<number|null> }>}
 *
 * Per active member, their rank (1 = most attended) by cumulative attendance
 * count at the end of each month that had at least one run. `ranks` is a
 * 12-element array indexed by month (0 = Jan .. 11 = Dec): months with no runs
 * are null (no movement to plot). Ties get distinct ranks by stable member
 * order (sorted by name) so the bump chart is deterministic. Lower priority;
 * lightly tested.
 */
export function rankByMonth(data) {
  if (!data || !Array.isArray(data.members)) return []
  const sorted = datedRunsSorted(data.runs)
  if (sorted.length === 0) return []

  // Active members only (anyone with >0 attended dated runs).
  const cumulative = {}
  const attendedAny = new Set()
  for (const run of sorted) {
    for (const name of data.members) {
      if (run.attendance?.[name]) attendedAny.add(name)
    }
  }
  const members = data.members.filter((m) => attendedAny.has(m))
  members.forEach((m) => {
    cumulative[m] = 0
  })

  // Which months actually had runs.
  const monthsWithRuns = new Set(sorted.map((r) => r.parsedDate.getMonth()))

  // Per member, a 12-slot rank array (null where no run that month).
  const ranks = {}
  members.forEach((m) => {
    ranks[m] = new Array(12).fill(null)
  })

  for (let month = 0; month < 12; month++) {
    // Accumulate this month's attendance into the running totals.
    for (const run of sorted) {
      if (run.parsedDate.getMonth() !== month) continue
      for (const m of members) {
        if (run.attendance?.[m]) cumulative[m] += 1
      }
    }
    if (!monthsWithRuns.has(month)) continue
    // Rank members by cumulative attendance desc; deterministic tiebreak by name.
    const ordered = members
      .slice()
      .sort((a, b) => cumulative[b] - cumulative[a] || (a < b ? -1 : a > b ? 1 : 0))
    ordered.forEach((m, i) => {
      ranks[m][month] = i + 1
    })
  }

  return members.map((name) => ({ name, ranks: ranks[name] }))
}
