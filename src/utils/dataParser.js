import Papa from 'papaparse'

// Member names from the CSV columns (row 10)
const MEMBER_COLUMNS = [
  'Aaron', 'Adam', 'Alex 👑', 'Alex Kr', 'Anna', 'Cam', 'Celeste', 'Chartt',
  'Claire', 'Col', 'Dan', 'Darren', 'Fraser', 'Grant', 'Jack', 'Joe',
  'Kate B', 'Laura E', 'Laura K', 'Liam', 'Ming', 'Rhys', 'Rohan', 'Sam',
  'Scott', 'Shane', 'Tarquin', 'Tim', 'Toby', 'Wes'
]

export function parseRunData(csvText) {
  const lines = csvText.split('\n')

  // Extract member totals from rows 8-9
  const kmRow = lines[7] // Row 8 (0-indexed = 7)
  const attendanceRow = lines[8] // Row 9 (0-indexed = 8)

  const kmParts = kmRow.split(',')
  const attendanceParts = attendanceRow.split(',')

  // Member totals are in columns 5-34 (matching header: Date, Meet, Run, Approx kms, Actual kms, then members)
  // Note: Row 8 has text in first 4 columns, but member km values still align at index 5+
  const memberTotals = {}
  MEMBER_COLUMNS.forEach((member, i) => {
    const kmValue = parseFloat(kmParts[5 + i]) || 0
    const attendanceValue = parseInt(attendanceParts[5 + i]) || 0
    memberTotals[member] = {
      name: member,
      totalKm: kmValue,
      totalRuns: attendanceValue
    }
  })

  // Parse header row to get column indices
  const headerRow = lines[9] // Row 10 (0-indexed = 9)
  const headers = Papa.parse(headerRow).data[0]

  // Parse run data starting from row 11 (index 10)
  const runData = []
  for (let i = 10; i < lines.length; i++) {
    const line = lines[i].trim()
    if (!line) continue

    const parsed = Papa.parse(line).data[0]
    if (!parsed || parsed.length < 5) continue

    const date = parsed[0]
    const meet = parsed[1]
    const runType = parsed[2]
    const approxKm = parseFloat(parsed[3]) || 0
    const actualKm = parseFloat(parsed[4]) || 0

    // Skip future runs (no actual km recorded and no attendance)
    const totalAttendance = parseInt(parsed[parsed.length - 2]) || 0
    if (totalAttendance === 0 && !actualKm) continue

    // Get attendance for each member
    const attendance = {}
    MEMBER_COLUMNS.forEach((member, idx) => {
      const value = parsed[5 + idx]
      // 'x' means attended, '-' might mean something specific, emoji = attended
      attendance[member] = value === 'x' || (value && value !== '-' && value !== '')
    })

    const plusOnes = parseInt(parsed[parsed.length - 3]) || 0
    const aggregateKm = parseFloat(parsed[parsed.length - 1]) || 0

    // Parse the date
    const dateMatch = date.match(/(\w+),\s+(\d+)-(\w+)/)
    let parsedDate = null
    if (dateMatch) {
      const [, dayOfWeek, day, month] = dateMatch
      const monthMap = {
        'Jan': 0, 'Feb': 1, 'Mar': 2, 'Apr': 3, 'May': 4, 'Jun': 5,
        'Jul': 6, 'Aug': 7, 'Sep': 8, 'Oct': 9, 'Nov': 10, 'Dec': 11
      }
      parsedDate = new Date(2025, monthMap[month], parseInt(day))
    }

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
      attendees: Object.entries(attendance)
        .filter(([, attended]) => attended)
        .map(([name]) => name)
    })
  }

  // Calculate additional stats
  const totalClubKm = Object.values(memberTotals).reduce((sum, m) => sum + m.totalKm, 0)
  const totalAttendanceInstances = Object.values(memberTotals).reduce((sum, m) => sum + m.totalRuns, 0)

  // Get runs by type
  const runsByType = {}
  runData.forEach(run => {
    const type = normalizeRunType(run.runType)
    if (!runsByType[type]) {
      runsByType[type] = { count: 0, totalKm: 0, totalAttendance: 0 }
    }
    runsByType[type].count++
    runsByType[type].totalKm += run.actualKm || 0
    runsByType[type].totalAttendance += run.totalAttendance
  })

  // Get runs by location
  const runsByLocation = {}
  runData.forEach(run => {
    if (!runsByLocation[run.meet]) {
      runsByLocation[run.meet] = { count: 0, totalKm: 0, totalAttendance: 0 }
    }
    runsByLocation[run.meet].count++
    runsByLocation[run.meet].totalKm += run.actualKm || 0
    runsByLocation[run.meet].totalAttendance += run.totalAttendance
  })

  // Get runs by month
  const runsByMonth = {}
  runData.forEach(run => {
    if (!run.parsedDate) return
    const month = run.parsedDate.toLocaleString('default', { month: 'short' })
    if (!runsByMonth[month]) {
      runsByMonth[month] = { count: 0, totalKm: 0, totalAttendance: 0 }
    }
    runsByMonth[month].count++
    runsByMonth[month].totalKm += run.actualKm || 0
    runsByMonth[month].totalAttendance += run.totalAttendance
  })

  // Leaderboard
  const leaderboard = Object.values(memberTotals)
    .filter(m => m.totalRuns > 0)
    .sort((a, b) => b.totalRuns - a.totalRuns)

  // Distance leaderboard
  const distanceLeaderboard = Object.values(memberTotals)
    .filter(m => m.totalKm > 0)
    .sort((a, b) => b.totalKm - a.totalKm)

  return {
    runs: runData,
    members: MEMBER_COLUMNS,
    memberTotals,
    leaderboard,
    distanceLeaderboard,
    totalRuns: runData.length,
    totalClubKm,
    totalAttendanceInstances,
    runsByType,
    runsByLocation,
    runsByMonth,
    avgAttendance: totalAttendanceInstances / runData.length
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

export { MEMBER_COLUMNS }
