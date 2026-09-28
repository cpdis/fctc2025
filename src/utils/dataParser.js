import Papa from 'papaparse'
import { normalizeLocation, parseRunLabel, runId } from './runLabels.js'

// Fixed columns that precede the dynamic member list in both the 2025 and 2026 sheets.
const FIXED_LEADING_COLS = ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms']

// Month prefixes, lowercased, in the same order as Apps Script's MONTH_ABBREVS.
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']

// Weekday names in Date#getDay() order (Sunday = 0).
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

// The sheet's run-date cell, matched exactly as Apps Script's parseSheetDate
// (apps-script/SheetOps.js) matches it: a 1-2 digit day, a "-", "/" or space,
// then a month word of 3+ letters, anywhere in the cell. The weekday and comma
// are optional, so "Fri, 3-Jan", "Sat 4-Oct", "26-Jan", "Thurs, 2-Oct" and
// "Sat, 4-Sept" are run dates on both stacks.
const RUN_DATE_PATTERN = /(\d{1,2})\s*[-/ ]\s*([A-Za-z]{3,})/

/**
 * Read a run-date cell into a local-midnight Date for the season year, plus
 * the weekday that date falls on.
 *
 * The weekday comes from the calendar, never from the typed text: a copied row
 * that reads "Wed, 2-Oct" in 2026 is a Friday, as the Swift kit also counts it.
 * The month is the first three letters of the month word in any case ("Sept"
 * is September), the same as Apps Script.
 *
 * Returns null for anything that is not a real calendar date: metadata labels
 * ("BIRTHDAY", "Notes"), unknown month names, and impossible days. Apps Script
 * lets "31-Sep" through (it checks only 1-31); the web rejects it rather than
 * misfile a run in October.
 */
function parseRunDate(cell, year) {
  const match = cell?.match(RUN_DATE_PATTERN)
  if (!match) return null
  const month = MONTHS.indexOf(match[2].slice(0, 3).toLowerCase())
  if (month === -1) return null
  const parsedDate = new Date(year, month, Number(match[1]))
  // new Date() rolls "31-Sep" into 1 Oct and "0-Oct" into 30 Sep; reject both.
  if (parsedDate.getMonth() !== month) return null
  return { parsedDate, dayOfWeek: WEEKDAYS[parsedDate.getDay()] }
}

/**
 * True when a member cell records attendance: its trimmed value is "x" in any
 * case (R1). Organisers leave notes in cells ("🛕", "sad face", "-", a time
 * like "12.30"); none of them mean the member ran. This is the one attendance
 * rule for every stack, and the sheet's own summary row counts the same way.
 */
function isAttended(cell) {
  return (cell ?? '').trim().toLowerCase() === 'x'
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
 * A run is a dated row with at least one attendee or +1 (R2), and a member
 * attended only when their cell is "x" (R1, see isAttended).
 *
 * All totals are COMPUTED from the data rows; the sheets' own summary rows are
 * never read. Under the rules above, each member's total matches the summary row
 * above the header (the snapshot tests check it).
 *
 * Each run keeps the sheet's own labels (`runType` without footnote markers,
 * `meet` as typed) for Wrapped, and gains the normalized `type`, `event` and
 * `location` plus a stable `id` from ./runLabels.js for everything else.
 * `rawRun` is the "Run" cell exactly as typed ("**Cruise"), which the golden
 * parity fixtures hand to the Swift label parser.
 *
 * `upcoming` lists the scheduled runs still to come: dated rows after the
 * season's latest run with nobody on them yet, each with the id it will keep
 * once it is recorded. They never count as runs.
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
  // Names are trimmed (above) and NFC-normalized, so "René" typed with a
  // combining accent is the same member as the precomposed one on every stack.
  const members = headers.slice(memberStart, plusOnesIndex).map((name) => name.normalize('NFC'))

  // Seed member totals so every member appears even if they attended nothing.
  const memberTotals = {}
  members.forEach((m) => {
    memberTotals[m] = { name: m, totalKm: 0, totalRuns: 0 }
  })

  // --- Parse data rows (everything after the header). ---
  const runData = []
  // Dated rows nobody has run yet; the ones after the latest run are upcoming.
  const unrecorded = []
  // Ids given out so far this season, so a same-date, same-label row gets "-2".
  const runIds = new Set()
  for (let i = headerIndex + 1; i < rows.length; i++) {
    const parsed = rows[i]
    if (!Array.isArray(parsed) || parsed.length < FIXED_LEADING_COLS.length) continue

    // A run row starts with its date ("Fri, 3-Jan", see parseRunDate). Anything
    // else under the header is sheet metadata, not a run. The BIRTHDAY row is
    // the live example: its member cells hold dates like "1-Sep", which would
    // otherwise read as attendance and add a phantom, undated run.
    const date = parsed[0]?.trim()
    const runDate = parseRunDate(date, year)
    if (!runDate) continue

    const meet = parsed[1]
    const { label, type, event } = parseRunLabel(parsed[2])
    const approxKm = parseFloat(parsed[3]) || 0
    const actualKm = parseFloat(parsed[4]) || 0

    // Every dated row takes its id here, in sheet order, recorded or not. So
    // recording an earlier same-date, same-label row later never shifts the
    // id of a run that is already recorded (and maybe linked), and a
    // scheduled row keeps its id once it is recorded.
    const id = runId(runDate.parsedDate, label, runIds)

    // Attendance per member, read by the member's column index (R1).
    const attendance = {}
    members.forEach((member, idx) => {
      attendance[member] = isAttended(parsed[memberStart + idx])
    })

    const attendees = members.filter((m) => attendance[m])
    const plusOnes = parseInt(parsed[plusOnesIndex]) || 0
    const totalAttendance = attendees.length + plusOnes

    // A run needs someone on it (R2). A dated row with nobody is a future or
    // unrecorded run, even when a distance was typed in ahead of time.
    if (totalAttendance === 0) {
      unrecorded.push({
        id,
        ...runDate,
        type,
        event,
        location: normalizeLocation(meet),
        approxKm,
      })
      continue
    }

    const aggregateKm = actualKm * totalAttendance

    // Accumulate per-member totals from the data itself.
    attendees.forEach((m) => {
      memberTotals[m].totalRuns += 1
      memberTotals[m].totalKm += actualKm
    })

    runData.push({
      id,
      date,
      parsedDate: runDate.parsedDate,
      dayOfWeek: runDate.dayOfWeek,
      meet,
      location: normalizeLocation(meet),
      rawRun: parsed[2],
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
  return aggregate({ runs: runData, members, memberTotals, upcoming: stillToCome(unrecorded, runData) })
}

/**
 * The scheduled rows still to come, in date order: those dated after the
 * latest run. A blank row before it (Fri 8 May 2026) is a run nobody recorded,
 * not a future one. Before a season's first run, every scheduled row is ahead.
 *
 * @param {Array<{ parsedDate: Date }>} scheduled - dated rows with nobody on them
 * @param {Array<{ parsedDate: Date }>} runs - the recorded runs
 */
function stillToCome(scheduled, runs) {
  // -Infinity when there are no runs yet, so every row passes.
  const latest = Math.max(...runs.map((run) => run.parsedDate.getTime()))
  return scheduled
    .filter((row) => row.parsedDate.getTime() > latest)
    .sort((a, b) => a.parsedDate - b.parsedDate)
}

/**
 * Roll parsed rows and per-member totals up into the full dashboard dataset.
 *
 * Every derived figure (club totals, leaderboards, runs-by-type/location/month,
 * averages) is computed here from `runs` + `memberTotals` so parseRunData (one
 * year) and combineYearData (all years merged) produce an identical shape.
 * `upcoming` passes through untouched; it never feeds a total.
 *
 * @param {{ runs: Array, members: string[], memberTotals: Object, upcoming: Array }} parsed
 */
function aggregate({ runs, members, memberTotals, upcoming }) {
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
    upcoming,
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
 *  - upcoming:    every season's scheduled rows still ahead of the latest run
 *                 of all, in date order.
 *
 * Everything downstream (leaderboards, totals, by-type/location/month, averages)
 * is then recomputed by aggregate(), so an all-time view is internally
 * consistent with each single-year view.
 *
 * @param {Array<ReturnType<typeof parseRunData>>} datasets
 */
export function combineYearData(datasets) {
  const present = (datasets ?? []).filter(Boolean)
  if (present.length === 0) return aggregate({ runs: [], members: [], memberTotals: {}, upcoming: [] })
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

  const upcoming = stillToCome(present.flatMap((data) => data.upcoming ?? []), runs)
  return aggregate({ runs, members, memberTotals, upcoming })
}
