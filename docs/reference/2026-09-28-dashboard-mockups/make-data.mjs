// Builds data.js for the round-1 mockups from the committed season CSVs.
// Applies the proposed rules without touching src/: only "x" counts as
// attendance, and streaks count Mon/Wed/Fri club days (any run that day).
import fs from 'node:fs'
import { join } from 'node:path'
import Papa from 'papaparse'
import { parseRunData, combineYearData } from '../../../src/utils/dataParser.js'

// Run from anywhere: `node docs/reference/2026-09-28-dashboard-mockups/make-data.mjs`.
process.chdir(join(import.meta.dirname, '../../..'))

const CLUB_DAYS = new Set(['Mon', 'Wed', 'Fri'])

// Blank every member cell that is not an "x" before parsing (x-only rule).
function xOnly(csv) {
  const rows = Papa.parse(csv).data
  const h = rows.findIndex((r) => r[0]?.trim() === 'Date' && r.includes('Actual kms'))
  const a = rows[h].indexOf('Actual kms')
  const p = rows[h].indexOf("+1's")
  for (let i = h + 1; i < rows.length; i++) {
    for (let c = a + 1; c < p; c++) {
      if ((rows[i][c] ?? '').trim().toLowerCase() !== 'x') rows[i][c] = ''
    }
  }
  return Papa.unparse(rows)
}

const load = (y) => parseRunData(xOnly(fs.readFileSync(`public/data/${y}.csv`, 'utf8')), y)
const d25 = load(2025)
const d26 = load(2026)
const all = combineYearData([d25, d26])

const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

// Club days in order; a member "made" a day when they attended any run on it.
function clubDays(data) {
  const days = new Map()
  for (const r of data.runs) {
    if (!CLUB_DAYS.has(r.dayOfWeek)) continue
    const k = iso(r.parsedDate)
    if (!days.has(k)) days.set(k, [])
    days.get(k).push(r)
  }
  return [...days.entries()].sort(([a], [b]) => (a < b ? -1 : 1))
}

function streaks(data, name) {
  const hits = clubDays(data).map(([k, runs]) => [k, runs.some((r) => r.attendance[name])])
  let current = 0
  for (let i = hits.length - 1; i >= 0 && hits[i][1]; i--) current++
  let best = 0, run = 0, bestEnd = -1
  hits.forEach(([, h], i) => { run = h ? run + 1 : 0; if (run > best) { best = run; bestEnd = i } })
  const currentFrom = current ? hits[hits.length - current][0] : null
  return { current, currentFrom, best, bestFrom: best ? hits[bestEnd - best + 1][0] : null, bestTo: best ? hits[bestEnd][0] : null }
}

const runs = d26.runs
  .slice()
  .sort((a, b) => a.parsedDate - b.parsedDate)
  .map((r, i) => ({
    i,
    date: iso(r.parsedDate),
    dow: r.dayOfWeek,
    club: CLUB_DAYS.has(r.dayOfWeek),
    meet: r.meet,
    type: r.runType,
    km: r.actualKm,
    runners: r.attendees,
    plusOnes: r.plusOnes,
    total: r.totalAttendance,
  }))

const members = d26.members
  .filter((m) => d26.memberTotals[m].totalRuns > 0)
  .map((m) => ({
    name: m,
    runs: d26.memberTotals[m].totalRuns,
    km: Math.round(d26.memberTotals[m].totalKm),
    allTime: all.memberTotals[m]?.totalRuns ?? 0,
    ...streaks(d26, m),
    attended: runs.filter((r) => r.runners.includes(m)).map((r) => r.i),
  }))
  .sort((a, b) => b.runs - a.runs || a.name.localeCompare(b.name))

// Cumulative member-km by day of year, for "vs last year".
function cumulative(data) {
  let km = 0
  return data.runs
    .slice()
    .sort((a, b) => a.parsedDate - b.parsedDate)
    .map((r) => {
      km += r.actualKm * r.attendees.length
      const start = new Date(r.parsedDate.getFullYear(), 0, 1)
      return { doy: Math.round((r.parsedDate - start) / 864e5), km: Math.round(km) }
    })
}

const last = runs[runs.length - 1]
const lastDoy = cumulative(d26).at(-1).doy
const km25AtSameDay = cumulative(d25).filter((p) => p.doy <= lastDoy).at(-1).km
const runs25AtSameDay = d25.runs.filter((r) => {
  const start = new Date(2025, 0, 1)
  return Math.round((r.parsedDate - start) / 864e5) <= lastDoy
}).length

// Upcoming scheduled rows (no attendance yet) straight from the sheet, for the Events tab.
const raw = Papa.parse(fs.readFileSync('public/data/2026.csv', 'utf8')).data
const hIdx = raw.findIndex((r) => r[0]?.trim() === 'Date' && r.includes('Actual kms'))
const upcoming = raw
  .slice(hIdx + 1)
  .filter((r) => /^\w{3},\s+\d{1,2}-\w{3}$/.test(r[0]?.trim() ?? '') && !(parseFloat(r[4]) > 0))
  .map((r) => {
    const [, day, mon] = r[0].match(/(\d{1,2})-(\w{3})/)
    const date = new Date(2026, ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'].indexOf(mon), +day)
    return { date: iso(date), dow: r[0].slice(0, 3), meet: r[1], type: r[2], km: parseFloat(r[3]) || null }
  })
  // Only rows after the latest recorded run are "coming up"; earlier blank rows are unrecorded.
  .filter((r) => r.date > runs[runs.length - 1].date)

const out = {
  season: 2026,
  updated: JSON.parse(fs.readFileSync('public/data/last-updated.json', 'utf8')).updatedAt,
  totals: {
    runs: d26.totalRuns,
    km: Math.round(d26.totalClubKm),
    runners: d26.leaderboard.length,
    perRun: +(d26.totalAttendanceInstances / d26.totalRuns).toFixed(1),
    lastRun: last.date,
    vsLastYear: { km: km25AtSameDay, runs: runs25AtSameDay },
  },
  runs,
  members,
  progress: { y2026: cumulative(d26), y2025: cumulative(d25) },
  upcoming,
  allTime: Object.values(all.memberTotals)
    .filter((m) => m.totalRuns > 0)
    .map((m) => ({ name: m.name, runs: m.totalRuns }))
    .sort((a, b) => b.runs - a.runs),
}

fs.writeFileSync('docs/reference/2026-09-28-dashboard-mockups/data.js', `window.FCTC = ${JSON.stringify(out)};\n`)
console.log('runs', out.totals, 'members', members.length, 'upcoming', upcoming.length)
console.log('streaks', members.filter((m) => m.current).sort((a, b) => b.current - a.current).slice(0, 5).map((m) => `${m.name} ${m.current}`))
console.log('milestones', out.allTime.map((m) => [m.name, m.runs, 50 - (m.runs % 50)]).sort((a, b) => a[2] - b[2]).slice(0, 5))
