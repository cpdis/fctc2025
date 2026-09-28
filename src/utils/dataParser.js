import Papa from 'papaparse'
import { normalizeLocation, parseRunLabel, runId } from './runLabels.js'

// Fixed columns that precede the dynamic member list in both the 2025 and 2026 sheets.
const FIXED_LEADING_COLS = ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms']

const MONTH_MAP = {
  Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
  Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11,
}

// The sheet's run-date cell: weekday, comma, day-month ("Fri, 3-Jan").
const RUN_DATE_PATTERN = /^(\w{3}),\s+(\d{1,2})-(\w{3})$/

/**
 * Read a run-date cell into a local-midnight Date for the season year.
 * Returns null for anything that is not a real calendar date in that format
 * (metadata labels, unknown month names, day 31 in a 30-day month).
 */
function parseRunDate(cell, year) {
  const match = cell?.match(RUN_DATE_PATTERN)
  if (!match) return null
  const [, dayOfWeek, dayText, monthText] = match
  const month = MONTH_MAP[monthText]
  const day = Number(dayText)
  if (month === undefined) return null
  const parsedDate = new Date(year, month, day)
  // new Date() rolls "31-Sep" into 1 Oct; reject it rather than misfile a run.
  if (parsedDate.getMonth() !== month) return null
  return { parsedDate, dayOfWeek }
}

/**
 * Parse the FCTC attendance CSV for a given year.
 *
 * Both the 2025 and 2026 sheets share the same general shape:
 *
 *   <noise / summary rows>           (variable count, differs per year)
 *   Date,Meet,Run,Approx kms,Actual kms,<member names...>,+1's,<trailing cols...>
 *   "Fri, 3-Jan",Il Lido,Soft Sand,7,7.07,x,,x,...,2,8,57
 *   ...
 *
 * The header row is found by content (first cell === "Date" and it contains
 * "Run" and "Actual kms"), so a drifting number of leading noise rows does not
 * break parsing. Member columns are everything AFTER "Actual kms" up to (but not
 * including) the "+1's" column, so 2025 yields 30 members and 2026 yields 33.
 *
 * All totals are COMPUTED from the data rows. The sheets' own summary rows use
 * COUNTUNIQUE etc. and have drifted between years, so we never read them.
 *
 * Each run keeps the sheet's own labels (`runType` without footnote markers,
 * `meet` as typed) for Wrapped, and gains the normalized `type`, `event` and
 * `location` plus a stable `id` from ./runLabels.js for everything else.
 *
 * @param {string} csvText - raw CSV contents
 * @param {number} year - calendar year used to build parsedDate
 */
export function parseRunData(csvText, year) {
  // Parse the whole sheet once. papaparse handles quoted fields, emoji, and
  // commas inside quotes, which a naive split(',') cannot.
  const rows = Papa.parse(csvText, { skipEmptyLines: false }).data

  // --- Locate the self-describing header row by content, not by index. ---
  const headerIndex = rows.findIndex(
    (row) =>
      Array.isArray(row) &&
      row[0]?.trim() === 'Date' &&
      row.includes('Run') &&
      row.includes('Actual kms')
  )
  if (headerIndex === -1) {
    throw new Error('Could not locate header row (first cell "Date" with "Run" and "Actual kms")')
  }
  const headers = rows[headerIndex].map((h) => (h ?? '').trim())

  // --- Derive the dynamic member list from the header. ---
  // Members live between the last fixed column ("Actual kms") and the "+1's" column.
  const actualKmIndex = headers.indexOf('Actual kms')
  const plusOnesIndex = headers.indexOf("+1's")
  if (actualKmIndex === -1 || plusOnesIndex === -1) {
    throw new Error('Header missing "Actual kms" or "+1\'s" column')
  }
  const memberStart = actualKmIndex + 1
  const members = headers.slice(memberStart, plusOnesIndex)

  // Seed member totals so every member appears even if they attended nothing.
  const memberTotals = {}
  members.forEach((m) => {
    memberTotals[m] = { name: m, totalKm: 0, totalRuns: 0 }
  })

  // --- Parse data rows (everything after the header). ---
  const runData = []
  // Ids given out so far this season, so a same-date, same-label row gets "-2".
  const runIds = new Set()
  for (let i = headerIndex + 1; i < rows.length; i++) {
    const parsed = rows[i]
    if (!Array.isArray(parsed) || parsed.length < FIXED_LEADING_COLS.length) continue

    // A run row starts with its date ("Fri, 3-Jan"). Anything else under the
    // header is sheet metadata, not a run. The BIRTHDAY row is the live example:
    // its member cells hold dates like "1-Sep", which would otherwise read as
    // attendance and add a phantom, undated run.
    const date = parsed[0]?.trim()
    const runDate = parseRunDate(date, year)
    if (!runDate) continue

    const meet = parsed[1]
    const { label, type, event } = parseRunLabel(parsed[2])
    const approxKm = parseFloat(parsed[3]) || 0
    const actualKm = parseFloat(parsed[4]) || 0

    // Attendance per member, read by the member's column index.
    const attendance = {}
    members.forEach((member, idx) => {
      const value = parsed[memberStart + idx]
      attendance[member] = value === 'x' || (value && value !== '-' && value !== '')
    })

    const attendees = members.filter((m) => attendance[m])
    const plusOnes = parseInt(parsed[plusOnesIndex]) || 0
    const totalAttendance = attendees.length + plusOnes

    // Skip rows that are clearly not real runs (future/blank): nobody attended
    // and no distance recorded.
    if (totalAttendance === 0 && !actualKm) continue

    const aggregateKm = actualKm * totalAttendance

    // Accumulate per-member totals from the data itself.
    attendees.forEach((m) => {
      memberTotals[m].totalRuns += 1
      memberTotals[m].totalKm += actualKm
    })

    runData.push({
      id: runId(runDate.parsedDate, label, runIds),
      date,
      parsedDate: runDate.parsedDate,
      dayOfWeek: runDate.dayOfWeek,
      meet,
      location: normalizeLocation(meet),
      runType: label,
      type,
      event,
      approxKm,
      actualKm,
      attendance,
      plusOnes,
      totalAttendance,
      aggregateKm,
      attendees,
    })
  }

  // Roll the parsed rows + per-member totals up into the dashboard shape. Kept
  // as a separate step so combineYearData() can reuse the EXACT same aggregation
  // over merged rows — there is one source of truth for every derived stat.
  return aggregate({ runs: runData, members, memberTotals })
}

/**
 * Roll parsed rows and per-member totals up into the full dashboard dataset.
 *
 * Every derived figure (club totals, leaderboards, runs-by-type/location/month,
 * averages) is computed here from `runs` + `memberTotals` so parseRunData (one
 * year) and combineYearData (all years merged) produce an identical shape.
 *
 * @param {{ runs: Array, members: string[], memberTotals: Object }} parsed
 */
function aggregate({ runs, members, memberTotals }) {
  // --- Club-wide totals, all computed from the data above. ---
  const totalClubKm = Object.values(memberTotals).reduce((sum, m) => sum + m.totalKm, 0)
  const totalAttendanceInstances = Object.values(memberTotals).reduce((sum, m) => sum + m.totalRuns, 0)

  // Runs by type.
  const runsByType = {}
  runs.forEach(({ type, actualKm, totalAttendance }) => {
    if (!runsByType[type]) {
      runsByType[type] = { count: 0, totalKm: 0, totalAttendance: 0 }
    }
    runsByType[type].count++
    runsByType[type].totalKm += actualKm || 0
    runsByType[type].totalAttendance += totalAttendance
  })

  // Runs by location.
  const runsByLocation = {}
  runs.forEach(({ location, actualKm, totalAttendance }) => {
    if (!runsByLocation[location]) {
      runsByLocation[location] = { count: 0, totalKm: 0, totalAttendance: 0 }
    }
    runsByLocation[location].count++
    runsByLocation[location].totalKm += actualKm || 0
    runsByLocation[location].totalAttendance += totalAttendance
  })

  // Runs by month.
  const runsByMonth = {}
  runs.forEach((run) => {
    if (!run.parsedDate) return
    const month = run.parsedDate.toLocaleString('default', { month: 'short' })
    if (!runsByMonth[month]) {
      runsByMonth[month] = { count: 0, totalKm: 0, totalAttendance: 0 }
    }
    runsByMonth[month].count++
    runsByMonth[month].totalKm += run.actualKm || 0
    runsByMonth[month].totalAttendance += run.totalAttendance
  })

  // Leaderboards.
  const leaderboard = Object.values(memberTotals)
    .filter((m) => m.totalRuns > 0)
    .sort((a, b) => b.totalRuns - a.totalRuns)

  const distanceLeaderboard = Object.values(memberTotals)
    .filter((m) => m.totalKm > 0)
    .sort((a, b) => b.totalKm - a.totalKm)

  return {
    runs,
    members,
    memberTotals,
    leaderboard,
    distanceLeaderboard,
    totalRuns: runs.length,
    totalClubKm,
    totalAttendanceInstances,
    runsByType,
    runsByLocation,
    runsByMonth,
    avgAttendance: runs.length > 0 ? totalAttendanceInstances / runs.length : 0,
  }
}

/**
 * Combine several parsed-year datasets into one "all time" dataset.
 *
 * Merges by:
 *  - runs:        concatenated (each run already carries its own dated
 *                 parsedDate, so chronology across years is preserved without
 *                 any re-dating). Run ids start with the full date, so they
 *                 stay unique across years.
 *  - members:     union, preserving first-seen order (a member who joined in a
 *                 later season still appears once).
 *  - memberTotals: summed per member across years (totalRuns / totalKm).
 *
 * Everything downstream (leaderboards, totals, by-type/location/month, averages)
 * is then recomputed by aggregate(), so an all-time view is internally
 * consistent with each single-year view.
 *
 * @param {Array<ReturnType<typeof parseRunData>>} datasets
 */
export function combineYearData(datasets) {
  const present = (datasets ?? []).filter(Boolean)
  if (present.length === 0) return aggregate({ runs: [], members: [], memberTotals: {} })
  if (present.length === 1) return present[0]

  const members = []
  const seen = new Set()
  const memberTotals = {}
  const runs = []

  for (const data of present) {
    for (const run of data.runs ?? []) runs.push(run)
    for (const name of data.members ?? []) {
      if (!seen.has(name)) {
        seen.add(name)
        members.push(name)
      }
      const yearTotals = data.memberTotals?.[name]
      if (!memberTotals[name]) memberTotals[name] = { name, totalKm: 0, totalRuns: 0 }
      if (yearTotals) {
        memberTotals[name].totalKm += yearTotals.totalKm || 0
        memberTotals[name].totalRuns += yearTotals.totalRuns || 0
      }
    }
  }

  return aggregate({ runs, members, memberTotals })
}
