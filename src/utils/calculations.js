// Calculate member-specific stats for Wrapped
export function calculateMemberStats(data, memberName) {
  const member = data.memberTotals[memberName]
  if (!member) return null

  // Get all runs this member attended
  const attendedRuns = data.runs.filter(run => run.attendance[memberName])

  // Favorite run type
  const runTypeCounts = {}
  attendedRuns.forEach(run => {
    const type = run.runType
    runTypeCounts[type] = (runTypeCounts[type] || 0) + 1
  })
  const favoriteRunType = Object.entries(runTypeCounts)
    .sort((a, b) => b[1] - a[1])[0]

  // Day preference (Wed vs Fri vs other)
  const dayPreference = { Wed: 0, Fri: 0, Other: 0 }
  attendedRuns.forEach(run => {
    if (run.dayOfWeek === 'Wed') dayPreference.Wed++
    else if (run.dayOfWeek === 'Fri') dayPreference.Fri++
    else dayPreference.Other++
  })

  // Calculate streak (consecutive scheduled runs attended)
  let currentStreak = 0
  let maxStreak = 0
  let tempStreak = 0

  data.runs.forEach(run => {
    if (run.attendance[memberName]) {
      tempStreak++
      maxStreak = Math.max(maxStreak, tempStreak)
    } else {
      tempStreak = 0
    }
  })

  // Check if currently on a streak
  for (let i = data.runs.length - 1; i >= 0; i--) {
    if (data.runs[i].attendance[memberName]) {
      currentStreak++
    } else {
      break
    }
  }

  // Peak month
  const monthCounts = {}
  attendedRuns.forEach(run => {
    if (run.parsedDate) {
      const month = run.parsedDate.toLocaleString('default', { month: 'short' })
      monthCounts[month] = (monthCounts[month] || 0) + 1
    }
  })
  const peakMonth = Object.entries(monthCounts)
    .sort((a, b) => b[1] - a[1])[0]

  // Monthly breakdown for this member (for chart display)
  const memberMonthlyData = {}
  Object.entries(monthCounts).forEach(([month, count]) => {
    memberMonthlyData[month] = { count, totalAttendance: count }
  })

  // Location preference
  const locationCounts = {}
  attendedRuns.forEach(run => {
    locationCounts[run.meet] = (locationCounts[run.meet] || 0) + 1
  })
  const favoriteLocation = Object.entries(locationCounts)
    .sort((a, b) => b[1] - a[1])[0]

  // Special events attended
  const specialEvents = attendedRuns.filter(run => {
    const type = run.runType.toLowerCase()
    return type.includes('half') || type.includes('mara') ||
           type.includes('cup') || type.includes('pancake') ||
           type.includes('10k')
  })

  // Rank
  const rank = data.leaderboard.findIndex(m => m.name === memberName) + 1
  const distanceRank = data.distanceLeaderboard.findIndex(m => m.name === memberName) + 1

  // Attendance rate
  const attendanceRate = (attendedRuns.length / data.runs.length) * 100

  // Co-runners (who they ran with most)
  const coRunnerCounts = {}
  attendedRuns.forEach(run => {
    run.attendees.forEach(attendee => {
      if (attendee !== memberName) {
        coRunnerCounts[attendee] = (coRunnerCounts[attendee] || 0) + 1
      }
    })
  })
  const topCoRunners = Object.entries(coRunnerCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)

  // Unique people ran with
  const uniqueCoRunners = Object.keys(coRunnerCounts).length

  return {
    name: memberName,
    totalRuns: member.totalRuns,
    totalKm: member.totalKm,
    avgKmPerRun: member.totalRuns > 0 ? member.totalKm / member.totalRuns : 0,
    rank,
    distanceRank,
    attendanceRate,
    favoriteRunType: favoriteRunType ? { type: favoriteRunType[0], count: favoriteRunType[1] } : null,
    dayPreference,
    maxStreak,
    currentStreak,
    peakMonth: peakMonth ? { month: peakMonth[0], count: peakMonth[1] } : null,
    monthlyData: memberMonthlyData,
    favoriteLocation: favoriteLocation ? { location: favoriteLocation[0], count: favoriteLocation[1] } : null,
    specialEvents,
    topCoRunners,
    uniqueCoRunners,
    attendedRuns
  }
}

// Calculate club-wide stats for Wrapped
export function calculateClubStats(data) {
  // Peak month for club
  const peakMonth = Object.entries(data.runsByMonth)
    .sort((a, b) => b[1].totalAttendance - a[1].totalAttendance)[0]

  // Most popular run type
  const popularRunType = Object.entries(data.runsByType)
    .sort((a, b) => b[1].count - a[1].count)[0]

  // Biggest run (most attendees)
  const biggestRun = [...data.runs].sort((a, b) => b.totalAttendance - a.totalAttendance)[0]

  // Longest run
  const longestRun = [...data.runs].sort((a, b) => b.actualKm - a.actualKm)[0]

  // The regulars (50%+ attendance)
  const regularThreshold = data.runs.length * 0.5
  const regulars = data.leaderboard.filter(m => m.totalRuns >= regularThreshold)

  // Special event participants
  const specialEventRuns = data.runs.filter(run => {
    const type = run.runType.toLowerCase()
    return type.includes('half') || type.includes('mara') ||
           type.includes('cup') || type.includes('10k')
  })

  const marathonFinishers = specialEventRuns
    .filter(r => r.runType.toLowerCase().includes('mara'))
    .flatMap(r => r.attendees)

  const halfMarathonFinishers = specialEventRuns
    .filter(r => r.runType.toLowerCase().includes('half'))
    .flatMap(r => r.attendees)

  // Day distribution
  const dayStats = { Wed: 0, Fri: 0, Other: 0 }
  data.runs.forEach(run => {
    if (run.dayOfWeek === 'Wed') dayStats.Wed += run.totalAttendance
    else if (run.dayOfWeek === 'Fri') dayStats.Fri += run.totalAttendance
    else dayStats.Other += run.totalAttendance
  })

  // Average attendance per month
  const monthlyAverages = {}
  Object.entries(data.runsByMonth).forEach(([month, stats]) => {
    monthlyAverages[month] = stats.count > 0 ? stats.totalAttendance / stats.count : 0
  })

  return {
    totalRuns: data.totalRuns,
    totalClubKm: data.totalClubKm,
    totalAttendanceInstances: data.totalAttendanceInstances,
    avgAttendance: data.avgAttendance,
    activeMembers: data.leaderboard.filter(m => m.totalRuns > 0).length,
    peakMonth: peakMonth ? { month: peakMonth[0], ...peakMonth[1] } : null,
    popularRunType: popularRunType ? { type: popularRunType[0], ...popularRunType[1] } : null,
    biggestRun,
    longestRun,
    regulars,
    marathonFinishers: [...new Set(marathonFinishers)],
    halfMarathonFinishers: [...new Set(halfMarathonFinishers)],
    dayStats,
    monthlyAverages,
    leaderboard: data.leaderboard.slice(0, 10),
    distanceLeaderboard: data.distanceLeaderboard.slice(0, 10)
  }
}

// Get a fun title based on member stats
export function getMemberTitle(stats) {
  if (!stats) return 'Runner'

  const titles = []

  // Based on attendance rank
  if (stats.rank === 1) titles.push('The Legend')
  else if (stats.rank <= 3) titles.push('Elite Runner')
  else if (stats.rank <= 5) titles.push('Dedicated Runner')
  else if (stats.rank <= 10) titles.push('Core Member')

  // Based on run type preference
  if (stats.favoriteRunType) {
    const type = stats.favoriteRunType.type.toLowerCase()
    if (type.includes('interval')) titles.push('Speed Demon')
    if (type.includes('soft sand')) titles.push('Beach Beast')
    if (type.includes('social')) titles.push('Social Butterfly')
    if (type.includes('hills')) titles.push('Hill Climber')
    if (type.includes('loop')) titles.push('Loop Legend')
  }

  // Based on streak
  if (stats.maxStreak >= 10) titles.push('Streak Master')

  // Based on distance
  if (stats.distanceRank === 1) titles.push('Distance King')
  else if (stats.distanceRank <= 3) titles.push('Endurance Champion')

  // Based on special events
  if (stats.specialEvents.some(e => e.runType.toLowerCase().includes('mara'))) {
    titles.push('Marathon Hero')
  }

  return titles[0] || 'Coffee Runner'
}
