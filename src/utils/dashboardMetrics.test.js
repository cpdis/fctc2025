import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from './dataParser'
import {
  cumulativeSeries,
  memberMonthlyAttendance,
  runTypeMonthlyCounts,
  firstVsSecondHalf,
  runFrequencyByDate,
  rankByMonth,
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

describe('memberMonthlyAttendance', () => {
  it.each(datasets)('%s: each member monthly array has length 12 and sums to totalRuns', (_, data) => {
    const rows = memberMonthlyAttendance(data)
    expect(rows.length).toBeGreaterThan(0)
    for (const row of rows) {
      expect(row.monthly).toHaveLength(12)
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
  it.each(datasets)('%s: each type monthly length 12 and sums to total', (_, data) => {
    const rows = runTypeMonthlyCounts(data)
    expect(rows.length).toBeGreaterThan(0)
    for (const row of rows) {
      expect(row.monthly).toHaveLength(12)
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

describe('rankByMonth (stretch)', () => {
  it.each(datasets)('%s: each member has a 12-slot ranks array', (_, data) => {
    const rows = rankByMonth(data)
    expect(rows.length).toBeGreaterThan(0)
    for (const row of rows) {
      expect(row.ranks).toHaveLength(12)
    }
  })

  it.each(datasets)('%s: ranks are 1..N in months that had runs, null otherwise', (_, data) => {
    const rows = rankByMonth(data)
    const n = rows.length
    // For each month, the non-null ranks should be a permutation of 1..n.
    for (let month = 0; month < 12; month++) {
      const vals = rows.map((r) => r.ranks[month]).filter((v) => v !== null)
      if (vals.length === 0) continue
      expect(vals.length).toBe(n)
      expect(new Set(vals).size).toBe(n)
      expect(Math.min(...vals)).toBe(1)
      expect(Math.max(...vals)).toBe(n)
    }
  })

  it('returns [] for degenerate input', () => {
    expect(rankByMonth(undefined)).toEqual([])
    expect(rankByMonth({ members: [], runs: [] })).toEqual([])
  })
})
