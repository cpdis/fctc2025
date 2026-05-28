import Papa from 'papaparse'

// Fixed columns that precede the dynamic member list in both the 2025 and 2026 sheets.
const FIXED_LEADING_COLS = ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms']

const MONTH_MAP = {
  Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
  Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11,
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
  for (let i = headerIndex + 1; i < rows.length; i++) {
    const parsed = rows[i]
    if (!Array.isArray(parsed) || parsed.length < FIXED_LEADING_COLS.length) continue

    const date = parsed[0]
    if (!date || !date.trim()) continue

    const meet = parsed[1]
    const runType = parsed[2]
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

    // Parse the date, e.g. "Fri, 3-Jan".
    const dateMatch = date.match(/(\w+),\s+(\d+)-(\w+)/)
    let parsedDate = null
    if (dateMatch) {
      const [, , day, month] = dateMatch
      parsedDate = new Date(year, MONTH_MAP[month], parseInt(day))
    }

    // Accumulate per-member totals from the data itself.
    attendees.forEach((m) => {
      memberTotals[m].totalRuns += 1
      memberTotals[m].totalKm += actualKm
    })

    runData.push({
      date,
      parsedDate,
      dayOfWeek: date.split(',')[0]?.trim(),
      meet,
      runType,
      approxKm,
      actualKm,
      attendance,
      plusOnes,
      totalAttendance,
      aggregateKm,
      attendees,
    })
  }

  // --- Club-wide totals, all computed from the data above. ---
  const totalClubKm = Object.values(memberTotals).reduce((sum, m) => sum + m.totalKm, 0)
  const totalAttendanceInstances = Object.values(memberTotals).reduce((sum, m) => sum + m.totalRuns, 0)

  // Runs by type.
  const runsByType = {}
  runData.forEach((run) => {
    const type = normalizeRunType(run.runType)
    if (!runsByType[type]) {
      runsByType[type] = { count: 0, totalKm: 0, totalAttendance: 0 }
    }
    runsByType[type].count++
    runsByType[type].totalKm += run.actualKm || 0
    runsByType[type].totalAttendance += run.totalAttendance
  })

  // Runs by location.
  const runsByLocation = {}
  runData.forEach((run) => {
    if (!runsByLocation[run.meet]) {
      runsByLocation[run.meet] = { count: 0, totalKm: 0, totalAttendance: 0 }
    }
    runsByLocation[run.meet].count++
    runsByLocation[run.meet].totalKm += run.actualKm || 0
    runsByLocation[run.meet].totalAttendance += run.totalAttendance
  })

  // Runs by month.
  const runsByMonth = {}
  runData.forEach((run) => {
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
    runs: runData,
    members,
    memberTotals,
    leaderboard,
    distanceLeaderboard,
    totalRuns: runData.length,
    totalClubKm,
    totalAttendanceInstances,
    runsByType,
    runsByLocation,
    runsByMonth,
    avgAttendance: runData.length > 0 ? totalAttendanceInstances / runData.length : 0,
  }
}

function normalizeRunType(type) {
  if (!type) return 'Other'
  const t = type.toLowerCase().trim()
  if (t.includes('interval')) return 'Intervals'
  if (t.includes('social')) return 'Social'
  if (t.includes('soft sand')) return 'Soft Sand'
  if (t.includes('lakes')) return 'Lakes Loop'
  if (t.includes('river')) return 'River Loop'
  if (t.includes('n/hood') || t.includes('neighbourhood')) return 'N\'hood Loop'
  if (t.includes('hills')) return 'Hills'
  if (t.includes('half')) return 'Half Marathon'
  if (t.includes('mara')) return 'Marathon'
  if (t.includes('10k')) return '10K'
  if (t.includes('cup')) return 'Filament Cup'
  if (t.includes('pancake')) return 'Special Event'
  return type
}
