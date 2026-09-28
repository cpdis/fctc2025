import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { LATEST_YEAR } from '../config/years'
import { parseRunData, combineYearData } from './dataParser'
import {
  headline,
  onARoll,
  wallModel,
  everyRunTracks,
  seasonProgress,
  cumulativeSeries,
  monthAxis,
  monthAxisLabel,
  memberMonthlyAttendance,
  runTypeMonthlyCounts,
  firstVsSecondHalf,
  runFrequencyByDate,
} from './dashboardMetrics'

// Under jsdom, import.meta.url is not a file: URL, so use import.meta.dirname.
const fixtureDir = join(import.meta.dirname, '..', 'test', 'fixtures')
const csv2025 = readFileSync(join(fixtureDir, '2025.csv'), 'utf-8')
const csv2026 = readFileSync(join(fixtureDir, '2026.csv'), 'utf-8')

const data2025 = parseRunData(csv2025, 2025)
const data2026 = parseRunData(csv2026, 2026)

const datasets = [
  ['2025', data2025],
  ['2026 (partial season)', data2026],
]

describe('cumulativeSeries', () => {
  it.each(datasets)('%s: cumulativeKm/Attendance/Runs are monotonic non-decreasing', (_, data) => {
    const series = cumulativeSeries(data.runs)
    expect(series.length).toBeGreaterThan(0)
    for (let i = 1; i < series.length; i++) {
      expect(series[i].cumulativeKm).toBeGreaterThanOrEqual(series[i - 1].cumulativeKm)
      expect(series[i].cumulativeAttendance).toBeGreaterThanOrEqual(series[i - 1].cumulativeAttendance)
      expect(series[i].cumulativeRuns).toBe(series[i - 1].cumulativeRuns + 1)
    }
  })

  it.each(datasets)('%s: final cumulativeKm equals sum of all dated runs actualKm', (_, data) => {
    const series = cumulativeSeries(data.runs)
    const dated = data.runs.filter((r) => r.parsedDate)
    const expectedKm = dated.reduce((s, r) => s + (r.actualKm || 0), 0)
    expect(series[series.length - 1].cumulativeKm).toBeCloseTo(expectedKm, 5)
  })

  it.each(datasets)('%s: final cumulativeRuns equals number of dated runs', (_, data) => {
    const series = cumulativeSeries(data.runs)
    const dated = data.runs.filter((r) => r.parsedDate)
    expect(series[series.length - 1].cumulativeRuns).toBe(dated.length)
    // Fixtures have parsedDate on every run, so this matches runs.length too.
    expect(series.length).toBe(dated.length)
  })

  it.each(datasets)('%s: final cumulativePersonKm reconciles with totalClubKm', (_, data) => {
    const series = cumulativeSeries(data.runs)
    expect(series[series.length - 1].cumulativePersonKm).toBeCloseTo(data.totalClubKm, 5)
  })

  it.each(datasets)('%s: cumulativePersonKm is monotonic non-decreasing', (_, data) => {
    const series = cumulativeSeries(data.runs)
    for (let i = 1; i < series.length; i++) {
      expect(series[i].cumulativePersonKm).toBeGreaterThanOrEqual(series[i - 1].cumulativePersonKm)
    }
  })

  it('is sorted ascending by date', () => {
    const series = cumulativeSeries(data2025.runs)
    for (let i = 1; i < series.length; i++) {
      expect(series[i].parsedDate.getTime()).toBeGreaterThanOrEqual(series[i - 1].parsedDate.getTime())
    }
  })

  it('returns [] for empty/degenerate input without throwing', () => {
    expect(cumulativeSeries([])).toEqual([])
    expect(cumulativeSeries(undefined)).toEqual([])
    expect(cumulativeSeries(null)).toEqual([])
  })
})

describe('monthAxis', () => {
  const keys = (runs) => monthAxis(runs).map((m) => m.key)

  const ym = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`

  it.each(datasets)('%s: runs from the first to the latest run month, no future months', (_, data) => {
    const dates = data.runs.map((r) => r.parsedDate).sort((a, b) => a - b)
    const axis = keys(data.runs)
    expect(axis[0]).toBe(ym(dates[0]))
    expect(axis.at(-1)).toBe(ym(dates.at(-1)))
  })

  it.each(datasets)('%s: months are contiguous', (_, data) => {
    const axis = monthAxis(data.runs)
    for (let i = 1; i < axis.length; i++) {
      const prev = axis[i - 1]
      expect(axis[i].year * 12 + axis[i].month).toBe(prev.year * 12 + prev.month + 1)
    }
  })

  it('keeps seasons apart in the all-time view', () => {
    const axis = keys(combineYearData([data2025, data2026]).runs)
    expect(axis[0]).toBe('2025-01')
    expect(axis).toContain('2025-06')
    expect(axis).toContain('2026-01')
    expect(new Set(axis).size).toBe(axis.length)
  })

  it('returns [] for empty input', () => {
    expect(monthAxis([])).toEqual([])
    expect(monthAxis(undefined)).toEqual([])
  })
})

describe('monthAxisLabel', () => {
  const run = (y, m) => ({ parsedDate: new Date(y, m, 5) })

  it('labels a single month, one year, and a cross-year range', () => {
    expect(monthAxisLabel(monthAxis([run(2026, 8)]))).toBe('Sep 2026')
    expect(monthAxisLabel(monthAxis([run(2026, 0), run(2026, 8)]))).toBe('Jan–Sep 2026')
    expect(monthAxisLabel(monthAxis([run(2025, 0), run(2026, 8)]))).toBe('Jan 2025–Sep 2026')
  })

  it('returns an empty string for an empty axis', () => {
    expect(monthAxisLabel([])).toBe('')
  })
})

describe('memberMonthlyAttendance', () => {
  it.each(datasets)('%s: each member monthly array spans the month axis and sums to totalRuns', (_, data) => {
    const rows = memberMonthlyAttendance(data)
    expect(rows.length).toBeGreaterThan(0)
    for (const row of rows) {
      expect(row.monthly).toHaveLength(monthAxis(data.runs).length)
      const sum = row.monthly.reduce((s, n) => s + n, 0)
      expect(sum).toBe(row.totalRuns)
    }
  })

  it.each(datasets)('%s: sorted by totalRuns desc', (_, data) => {
    const rows = memberMonthlyAttendance(data)
    for (let i = 1; i < rows.length; i++) {
      expect(rows[i - 1].totalRuns).toBeGreaterThanOrEqual(rows[i].totalRuns)
    }
  })

  it.each(datasets)('%s: zero-attendance members are excluded', (_, data) => {
    const rows = memberMonthlyAttendance(data)
    expect(rows.every((r) => r.totalRuns > 0)).toBe(true)
    // A member present in the sheet with zero attended runs must not appear.
    const zeroMembers = data.members.filter((m) => data.memberTotals[m].totalRuns === 0)
    for (const zm of zeroMembers) {
      expect(rows.find((r) => r.name === zm)).toBeUndefined()
    }
  })

  it.each(datasets)('%s: totalRuns/totalKm match parser memberTotals', (_, data) => {
    const rows = memberMonthlyAttendance(data)
    for (const row of rows) {
      expect(row.totalRuns).toBe(data.memberTotals[row.name].totalRuns)
      expect(row.totalKm).toBeCloseTo(data.memberTotals[row.name].totalKm, 5)
    }
  })

  it.each(datasets)('%s: currentStreak is a non-negative integer', (_, data) => {
    const rows = memberMonthlyAttendance(data)
    for (const row of rows) {
      expect(Number.isInteger(row.currentStreak)).toBe(true)
      expect(row.currentStreak).toBeGreaterThanOrEqual(0)
    }
  })

  it('returns [] for degenerate input', () => {
    expect(memberMonthlyAttendance(undefined)).toEqual([])
    expect(memberMonthlyAttendance({})).toEqual([])
  })
})

describe('runTypeMonthlyCounts', () => {
  it.each(datasets)('%s: each type monthly spans the month axis and sums to total', (_, data) => {
    const rows = runTypeMonthlyCounts(data)
    expect(rows.length).toBeGreaterThan(0)
    for (const row of rows) {
      expect(row.monthly).toHaveLength(monthAxis(data.runs).length)
      const sum = row.monthly.reduce((s, n) => s + n, 0)
      expect(sum).toBe(row.total)
    }
  })

  it.each(datasets)('%s: total run count across types equals number of dated runs', (_, data) => {
    const rows = runTypeMonthlyCounts(data)
    const totalAcrossTypes = rows.reduce((s, r) => s + r.total, 0)
    const datedRuns = data.runs.filter((r) => r.parsedDate).length
    expect(totalAcrossTypes).toBe(datedRuns)
  })

  it.each(datasets)('%s: sorted by total desc', (_, data) => {
    const rows = runTypeMonthlyCounts(data)
    for (let i = 1; i < rows.length; i++) {
      expect(rows[i - 1].total).toBeGreaterThanOrEqual(rows[i].total)
    }
  })

  it('returns [] for degenerate input', () => {
    expect(runTypeMonthlyCounts(undefined)).toEqual([])
    expect(runTypeMonthlyCounts({ runs: [] })).toEqual([])
  })
})

describe('firstVsSecondHalf', () => {
  it.each(datasets)('%s: first+second equals member total attended runs', (_, data) => {
    const rows = firstVsSecondHalf(data)
    expect(rows.length).toBeGreaterThan(0)
    for (const row of rows) {
      expect(row.first + row.second).toBe(data.memberTotals[row.name].totalRuns)
    }
  })

  it('2026 split point is derived from data, not June', () => {
    const sorted = data2026.runs
      .filter((r) => r.parsedDate)
      .slice()
      .sort((a, b) => a.parsedDate - b.parsedDate)
    const start = sorted[0].parsedDate
    const end = sorted[sorted.length - 1].parsedDate

    // Partial season: spans only a handful of months (sanity: < 8).
    const spanMonths = (end.getFullYear() - start.getFullYear()) * 12 + (end.getMonth() - start.getMonth())
    expect(spanMonths).toBeLessThan(8)

    // The true midpoint is NOT pinned to June (month index 5). For a season that
    // starts in Jan and ends ~May, the midpoint lands well before June.
    const midpoint = new Date(start.getTime() + (end.getTime() - start.getTime()) / 2)
    expect(midpoint.getMonth()).toBeLessThan(5)

    // Function still produces sensible halves on the short season.
    const rows = firstVsSecondHalf(data2026)
    expect(rows.every((r) => r.first >= 0 && r.second >= 0)).toBe(true)
    // At least some members have runs on both sides of the derived split.
    expect(rows.some((r) => r.first > 0 && r.second > 0)).toBe(true)
  })

  it.each(datasets)('%s: excludes zero-attendance members', (_, data) => {
    const rows = firstVsSecondHalf(data)
    expect(rows.every((r) => r.first + r.second > 0)).toBe(true)
  })

  it('returns [] for degenerate input', () => {
    expect(firstVsSecondHalf(undefined)).toEqual([])
    expect(firstVsSecondHalf({ members: [], runs: [] })).toEqual([])
  })
})

describe('runFrequencyByDate', () => {
  it.each(datasets)('%s: entries only for real run dates, counts positive', (_, data) => {
    const entries = runFrequencyByDate(data.runs)
    expect(entries.length).toBeGreaterThan(0)

    const realDays = new Set(
      data.runs
        .filter((r) => r.parsedDate)
        .map((r) => {
          const d = r.parsedDate
          return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
        })
    )
    for (const e of entries) {
      expect(e.count).toBeGreaterThan(0)
      expect(realDays.has(e.date)).toBe(true)
    }
    // One entry per distinct run day.
    expect(entries.length).toBe(realDays.size)
  })

  it.each(datasets)('%s: count is total attendance per day', (_, data) => {
    const entries = runFrequencyByDate(data.runs)
    const byDay = new Map(entries.map((e) => [e.date, e.count]))
    // Pick a day and verify the count equals summed totalAttendance there.
    const sample = entries[0].date
    const expected = data.runs
      .filter((r) => {
        if (!r.parsedDate) return false
        const d = r.parsedDate
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
        return key === sample
      })
      .reduce((s, r) => s + (r.totalAttendance || 0), 0)
    expect(byDay.get(sample)).toBe(expected)
  })

  it('is sorted ascending by date', () => {
    const entries = runFrequencyByDate(data2025.runs)
    for (let i = 1; i < entries.length; i++) {
      expect(entries[i - 1].date <= entries[i].date).toBe(true)
    }
  })

  it('returns [] for empty input', () => {
    expect(runFrequencyByDate([])).toEqual([])
    expect(runFrequencyByDate(undefined)).toEqual([])
  })
})

// ---------------------------------------------------------------------------
// Poster dashboard builders, pinned to the dated snapshot of the live sheets
// (27 Sep 2026: latest run Fri 25 Sep, the BIRTHDAY row, the 2025 annotation
// cells). The numbers match the approved mockup's data.js.
// ---------------------------------------------------------------------------

const snapshotDir = join(import.meta.dirname, '..', '..', 'fixtures', 'attendance', '2026-09-27')
const snapshot = (year) => parseRunData(readFileSync(join(snapshotDir, `${year}.csv`), 'utf-8'), year)
const snap2025 = snapshot(2025)
const snap2026 = snapshot(2026)
// Newest season first, the order the app loads them in.
const snapAllTime = combineYearData([snap2026, snap2025])

/**
 * A small season sheet for edge cases. Each row is
 * [date, run label, actual km, Ann, Bob, +1s]; an empty km and no one on it
 * makes a scheduled row.
 */
const season = (year, ...rows) =>
  parseRunData(
    [
      "Date,Meet,Run,Approx kms,Actual kms,Ann,Bob,+1's",
      ...rows.map(([date, run, km, ann, bob, plusOnes]) => `"${date}",Filament,${run},10,${km},${ann},${bob},${plusOnes}`),
    ].join('\n'),
    year
  )

describe('headline', () => {
  it('2026 against 2025 on the same date (Fri 25 Sep)', () => {
    const numbers = headline(snap2026, snap2025)
    expect(numbers).toMatchObject({ runs: 118, runners: 30 })
    expect(Math.round(numbers.memberKm)).toBe(9889)
    expect(numbers.perRun).toBeCloseTo(8.2, 1)

    const { vsPrevious } = numbers
    expect(vsPrevious).toMatchObject({ year: 2025, runs: 80, runsDelta: 38 })
    expect(Math.round(vsPrevious.memberKm)).toBe(8263)
    expect(vsPrevious.memberKmDelta).toBeCloseTo(numbers.memberKm - vsPrevious.memberKm, 6)
  })

  it('counts member-km and per run without +1s', () => {
    // Ann and Bob run 10 km with 3 guests: 20 member-km, 2 members per run.
    const numbers = headline(season(2026, ['Mon, 5-Jan', 'Cruise', '10', 'x', 'x', '3']))
    expect(numbers).toMatchObject({ runs: 1, memberKm: 20, runners: 2, perRun: 2 })
  })

  it('has no comparison without a previous season, or for All time', () => {
    expect(headline(snap2025).vsPrevious).toBeNull()
    expect(headline(snap2025, null).vsPrevious).toBeNull()
    expect(headline(snapAllTime, snap2025).vsPrevious).toBeNull()
    expect(headline(snapAllTime)).toMatchObject({ runs: 229, runners: 34 })
  })

  it('matches month and day, not day of year, across a leap year', () => {
    // Day 59 of 2028 is 29 Feb; day 59 of 2027 is 1 Mar, which must not count.
    const view = season(2028, ['Tue, 29-Feb', 'Cruise', '10', 'x', '', '0'])
    const previous = season(
      2027,
      ['Sun, 28-Feb', 'Cruise', '10', 'x', 'x', '0'],
      ['Mon, 1-Mar', 'Cruise', '10', 'x', 'x', '0']
    )
    expect(headline(view, previous).vsPrevious).toMatchObject({ year: 2027, runs: 1, memberKm: 20 })
  })

  it('reads zeros for a season with no runs yet', () => {
    const empty = season(2027, ['Mon, 4-Jan', 'Cruise', '', '', '', '0'])
    expect(headline(empty, snap2026)).toEqual({ runs: 0, memberKm: 0, runners: 0, perRun: 0, vsPrevious: null })
  })
})

describe('onARoll', () => {
  const names = (list) => list.map(({ name, streak }) => `${name} ${streak}`)

  it('2025 is at season end with Scott on 49 first (AE9)', () => {
    const roll = onARoll(snap2025)
    expect(roll.finished).toBe(true)
    expect(roll.current[0]).toEqual({ name: 'Scott', streak: 49, from: '2025-07-16' })
    expect(roll.bests[0]).toEqual({ name: 'Scott', streak: 54, from: '2025-01-03', to: '2025-07-09' })
    expect(roll.weekdays).toEqual(['Wed', 'Fri'])
  })

  it('2026 lists the top 5 current streaks and top 3 season bests, ties by runs', () => {
    const roll = onARoll(snap2026)
    // Scott and Kate B are both on 2; Scott has more runs.
    expect(names(roll.current)).toEqual(['Aaron 14', 'Cam 5', 'Scott 2', 'Kate B 2', 'Alex B 1'])
    expect(roll.current[0].from).toBe('2026-08-26')
    expect(roll.bests).toEqual([
      { name: 'Aaron', streak: 14, from: '2026-08-26', to: '2026-09-25' },
      { name: 'Alex 👑', streak: 9, from: '2026-01-02', to: '2026-01-21' },
      { name: 'Scott', streak: 5, from: '2026-01-21', to: '2026-01-30' },
    ])
    expect(roll.weekdays).toEqual(['Mon', 'Wed', 'Fri'])
  })

  it('All time counts streaks over the merged club days of both seasons', () => {
    const roll = onARoll(snapAllTime)
    expect(names(roll.current)).toEqual(names(onARoll(snap2026).current))
    expect(roll.bests[0]).toEqual({ name: 'Scott', streak: 54, from: '2025-01-03', to: '2025-07-09' })
  })

  it('a season still running is not finished, and nobody on 0 is listed', () => {
    // Ann made Mon 5 Jan, then nobody made Wed 7 Jan except a guest.
    const roll = onARoll(
      season(LATEST_YEAR, ['Mon, 5-Jan', 'Cruise', '10', 'x', '', '0'], ['Wed, 7-Jan', 'Social', '8', '', '', '1'])
    )
    expect(roll.finished).toBe(false)
    expect(roll.current).toEqual([])
    expect(names(roll.bests)).toEqual(['Ann 1'])
  })
})

describe('wallModel', () => {
  const wall2026 = wallModel(snap2026)
  const row = (wall, name) => wall.rows.find((r) => r.name === name)

  it('2026 has 30 active rows against 118 runs, most runs first', () => {
    expect(wall2026.rows).toHaveLength(30)
    expect(wall2026.columns).toHaveLength(118)
    expect(wall2026.rows.every((r) => r.cells.length === 118)).toBe(true)
    expect(wall2026.rows[0]).toMatchObject({ name: 'Aaron', runs: 89, current: 14 })
    // Fraser is on the 2026 sheet but has no runs yet.
    expect(row(wall2026, 'Fraser')).toBeUndefined()
  })

  it('columns run oldest first, and each cell mirrors the sheet', () => {
    const dates = wall2026.columns.map((c) => c.date)
    expect(dates).toEqual([...dates].sort())
    for (const r of wall2026.rows) {
      r.cells.forEach((cell, i) => expect(cell.ran).toBe(wall2026.columns[i].run.attendance[r.name]))
      expect(r.cells.filter((cell) => cell.ran)).toHaveLength(r.runs)
    }
  })

  it("Aaron's last 14 club-day cells are his streak; the Pub Run is not (AE1)", () => {
    const aaron = row(wall2026, 'Aaron')
    const club = wall2026.columns.flatMap((c, i) => (c.special ? [] : [i]))
    const lastFifteen = club.slice(-15).map((i) => aaron.cells[i].streak)
    expect(lastFifteen).toEqual([false, ...Array(14).fill(true)])
    expect(aaron.cells.filter((cell) => cell.streak)).toHaveLength(14)

    const pubRun = wall2026.columns.findIndex((c) => c.run.id === '2026-09-05-pub-run')
    expect(aaron.cells[pubRun]).toEqual({ ran: true, streak: false, special: true, notOnRoster: false })
  })

  it('marks the two Saturday specials (Anzac Day, Pub Run) and nothing else', () => {
    const specials = wall2026.columns.filter((c) => c.special)
    expect(specials.map((c) => c.run.id)).toEqual([
      '2026-04-25-mara-anzac-day',
      '2026-04-25-half-anzac-day',
      '2026-09-05-pub-run',
    ])
    expect(new Set(specials.map((c) => c.run.dayOfWeek))).toEqual(new Set(['Sat']))
    wall2026.columns.forEach((c, i) => {
      expect(wall2026.rows.every((r) => r.cells[i].special === c.special)).toBe(true)
    })
  })

  it('a single season has nobody off the roster', () => {
    expect(wall2026.rows.every((r) => r.cells.every((cell) => !cell.notOnRoster))).toBe(true)
  })

  it('All time marks Dan B, Deano and René off the roster before 2026', () => {
    const wall = wallModel(snapAllTime)
    const years = wall.columns.map((c) => c.run.parsedDate.getFullYear())
    for (const name of ['Dan B', 'Deano', 'René']) {
      const offRoster = row(wall, name).cells.map((cell) => cell.notOnRoster)
      expect(offRoster).toEqual(years.map((year) => year === 2025))
    }
    expect(row(wall, 'Aaron').cells.every((cell) => !cell.notOnRoster)).toBe(true)
    // Active in 2025, so Fraser is on the All time wall.
    expect(row(wall, 'Fraser').runs).toBe(19)
    expect(wall.columns).toHaveLength(229)
  })
})

describe('everyRunTracks', () => {
  const tracks2026 = everyRunTracks(snap2026)
  const track = (tracks, name) => tracks.find((t) => t.name === name)

  it('2026 has Monday, Wednesday, Friday and Specials, named for their usual spot', () => {
    expect(tracks2026.map((t) => [t.name, t.location])).toEqual([
      ['Mon', 'Drift'],
      ['Wed', 'Filament'],
      ['Fri', 'Il Lido'],
      ['Specials', 'Filament'],
    ])
    const runsInColumns = tracks2026.flatMap((t) => t.columns.flatMap((c) => c.runs))
    expect(runsInColumns).toHaveLength(118)
  })

  it('2025 has no Monday track; its Invasion Day Monday is a special', () => {
    const tracks = everyRunTracks(snap2025)
    expect(tracks.map((t) => t.name)).toEqual(['Wed', 'Fri', 'Specials'])
    expect(track(tracks, 'Specials').columns.map((c) => c.date)).toEqual(['2025-01-27', '2025-09-20', '2025-12-14'])
  })

  it('the 26 Jan column combines the Half and 10k runners (AE2)', () => {
    const column = track(tracks2026, 'Mon').columns.find((c) => c.date === '2026-01-26')
    expect(column.runs.map((r) => r.id)).toEqual(['2026-01-26-half-invasion-day', '2026-01-26-10k-invasion-day'])
    expect(column).toMatchObject({ members: 6, plusOnes: 1 })
  })

  it('labels each busiest day with its event, else its type, and the count', () => {
    expect(track(tracks2026, 'Wed').busiest).toEqual({ date: '2026-01-07', label: 'Social', count: 18 })
    expect(track(tracks2026, 'Fri').busiest).toEqual({ date: '2026-04-03', label: 'Good Friday', count: 10 })
    expect(track(tracks2026, 'Specials')).toMatchObject({
      busiest: { date: '2026-09-05', label: 'Pub Run', count: 18 },
      averageMembers: 11.5,
    })
  })

  it('gives one mark per runner when someone runs twice on one date', () => {
    const [specials] = everyRunTracks(
      season(2026, ['Sun, 13-Dec', 'Mara - Xmas', '42.2', 'x', '', '0'], ['Sun, 13-Dec', 'Half - Xmas', '21.1', 'x', 'x', '2'])
    )
    expect(specials.name).toBe('Specials')
    expect(specials.columns).toHaveLength(1)
    expect(specials.columns[0]).toMatchObject({ members: 2, plusOnes: 2 })
    expect(specials.busiest).toEqual({ date: '2026-12-13', label: 'Xmas', count: 4 })
  })

  it('has no tracks before the first run', () => {
    expect(everyRunTracks(combineYearData([]))).toEqual([])
  })
})

describe('seasonProgress', () => {
  const progress = seasonProgress(snap2026, snap2025)

  it('2026 ends on 9,889 member-km; 2025 had 8,263 by 25 Sep', () => {
    expect(progress.current.year).toBe(2026)
    expect(progress.previous.year).toBe(2025)
    const latest = progress.current.points.at(-1)
    expect(latest).toMatchObject({ date: '2026-09-25', dayOfYear: 267 })
    expect(Math.round(latest.memberKm)).toBe(9889)
    expect(Math.round(progress.previousAtLatest)).toBe(8263)
    expect(Math.round(progress.previous.points.at(-1).memberKm)).toBe(11165)
  })

  it('has one rising point per run date', () => {
    const { points } = progress.current
    // 118 runs on 116 dates: 26 Jan and 25 Apr each had two runs.
    expect(points).toHaveLength(116)
    expect(points[0]).toMatchObject({ date: '2026-01-02', dayOfYear: 1 })
    for (let i = 1; i < points.length; i++) {
      expect(points[i].dayOfYear).toBeGreaterThan(points[i - 1].dayOfYear)
      expect(points[i].memberKm).toBeGreaterThanOrEqual(points[i - 1].memberKm)
    }
  })

  it("previousAtLatest is last season's line on the latest run's date", () => {
    const upToDate = progress.previous.points.filter((p) => p.date <= '2025-09-25')
    expect(progress.previousAtLatest).toBeCloseTo(upToDate.at(-1).memberKm, 6)
  })

  it('is hidden without a previous season, and for All time', () => {
    expect(seasonProgress(snap2025, null)).toBeNull()
    expect(seasonProgress(snap2025)).toBeNull()
    expect(seasonProgress(snapAllTime, snap2025)).toBeNull()
  })
})
