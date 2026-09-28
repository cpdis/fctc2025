import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData, combineYearData } from './dataParser'

// Read fixtures relative to this test file so it works regardless of cwd.
const fixtureDir = join(import.meta.dirname, '..', 'test', 'fixtures')
const csv2025 = readFileSync(join(fixtureDir, '2025.csv'), 'utf-8')
const csv2026 = readFileSync(join(fixtureDir, '2026.csv'), 'utf-8')

const data2025 = parseRunData(csv2025, 2025)
const data2026 = parseRunData(csv2026, 2026)

describe('parseRunData - member detection', () => {
  it('detects exactly 30 members for 2025, including the emoji name', () => {
    expect(data2025.members).toHaveLength(30)
    expect(data2025.members).toContain('Alex 👑')
    expect(data2025.runs.length).toBeGreaterThan(0)
  })

  it('detects exactly 33 members for 2026, including new members and emoji name', () => {
    expect(data2026.members).toHaveLength(33)
    expect(data2026.members).toContain('Alex B')
    expect(data2026.members).toContain('Dan B')
    expect(data2026.members).toContain('Deano')
    expect(data2026.members).toContain('Alex 👑')
  })
})

describe('parseRunData - header detection by content', () => {
  it('parses both years despite different noise-row counts before the header', () => {
    // 2025 header is at line index 9, 2026 at index 10. Both must parse.
    expect(data2025.runs.length).toBeGreaterThan(0)
    expect(data2026.runs.length).toBeGreaterThan(0)
  })
})

describe('parseRunData - row filtering', () => {
  it('skips future/empty rows (no run has 0 attendance AND 0 actualKm)', () => {
    for (const data of [data2025, data2026]) {
      const ghost = data.runs.find((r) => r.totalAttendance === 0 && !r.actualKm)
      expect(ghost).toBeUndefined()
    }
  })
})

describe('parseRunData - computed member totals', () => {
  it("a member's totalKm equals the sum of actualKm over runs they attended", () => {
    const member = data2025.members.find((m) => data2025.memberTotals[m].totalRuns > 0)
    const expectedKm = data2025.runs
      .filter((r) => r.attendance[member])
      .reduce((sum, r) => sum + r.actualKm, 0)
    const expectedRuns = data2025.runs.filter((r) => r.attendance[member]).length

    expect(data2025.memberTotals[member].totalKm).toBeCloseTo(expectedKm, 5)
    expect(data2025.memberTotals[member].totalRuns).toBe(expectedRuns)
  })
})

describe('parseRunData - year handling', () => {
  it('uses the passed-in year for parsedDate', () => {
    const dated2026 = data2026.runs.filter((r) => r.parsedDate)
    expect(dated2026.length).toBeGreaterThan(0)
    for (const run of dated2026) {
      expect(run.parsedDate.getFullYear()).toBe(2026)
    }
  })
})

describe('combineYearData - all time', () => {
  const all = combineYearData([data2026, data2025])

  it('returns the single dataset unchanged when given one year', () => {
    expect(combineYearData([data2025])).toBe(data2025)
  })

  it('handles empty input without throwing', () => {
    const empty = combineYearData([])
    expect(empty.runs).toEqual([])
    expect(empty.totalRuns).toBe(0)
    expect(empty.avgAttendance).toBe(0)
  })

  it('concatenates every run across years', () => {
    expect(all.runs.length).toBe(data2025.runs.length + data2026.runs.length)
    expect(all.totalRuns).toBe(data2025.totalRuns + data2026.totalRuns)
  })

  it('unions members without duplicates (Alex 👑 is in both years, once combined)', () => {
    const union = new Set([...data2025.members, ...data2026.members])
    expect(all.members.length).toBe(union.size)
    expect(all.members.filter((m) => m === 'Alex 👑')).toHaveLength(1)
  })

  it('sums per-member totals across years for a member who ran in both', () => {
    const name = data2025.members.find(
      (m) =>
        data2026.members.includes(m) &&
        data2025.memberTotals[m].totalRuns > 0 &&
        data2026.memberTotals[m].totalRuns > 0
    )
    expect(name).toBeTruthy()
    expect(all.memberTotals[name].totalRuns).toBe(
      data2025.memberTotals[name].totalRuns + data2026.memberTotals[name].totalRuns
    )
    expect(all.memberTotals[name].totalKm).toBeCloseTo(
      data2025.memberTotals[name].totalKm + data2026.memberTotals[name].totalKm,
      5
    )
  })

  it('club totals are the sum of each year', () => {
    expect(all.totalClubKm).toBeCloseTo(data2025.totalClubKm + data2026.totalClubKm, 5)
    expect(all.totalAttendanceInstances).toBe(
      data2025.totalAttendanceInstances + data2026.totalAttendanceInstances
    )
  })

  it('preserves each run year on its own parsedDate', () => {
    const years = new Set(
      all.runs.filter((r) => r.parsedDate).map((r) => r.parsedDate.getFullYear())
    )
    expect(years.has(2025)).toBe(true)
    expect(years.has(2026)).toBe(true)
  })
})

describe('parseRunData - output contract', () => {
  it('returns all contract keys with the expected types', () => {
    const d = data2025
    expect(Array.isArray(d.runs)).toBe(true)
    expect(Array.isArray(d.members)).toBe(true)
    expect(typeof d.memberTotals).toBe('object')
    expect(Array.isArray(d.leaderboard)).toBe(true)
    expect(Array.isArray(d.distanceLeaderboard)).toBe(true)
    expect(typeof d.totalRuns).toBe('number')
    expect(typeof d.totalClubKm).toBe('number')
    expect(typeof d.totalAttendanceInstances).toBe('number')
    expect(typeof d.runsByType).toBe('object')
    expect(typeof d.runsByLocation).toBe('object')
    expect(typeof d.runsByMonth).toBe('object')
    expect(typeof d.avgAttendance).toBe('number')

    // Per-run shape.
    const run = d.runs[0]
    expect(run).toHaveProperty('date')
    expect(run).toHaveProperty('parsedDate')
    expect(run).toHaveProperty('dayOfWeek')
    expect(run).toHaveProperty('meet')
    expect(run).toHaveProperty('runType')
    expect(run).toHaveProperty('approxKm')
    expect(run).toHaveProperty('actualKm')
    expect(run).toHaveProperty('attendance')
    expect(run).toHaveProperty('plusOnes')
    expect(run).toHaveProperty('totalAttendance')
    expect(run).toHaveProperty('aggregateKm')
    expect(Array.isArray(run.attendees)).toBe(true)

    // memberTotals entry shape.
    const mt = d.memberTotals[d.members[0]]
    expect(mt).toHaveProperty('name')
    expect(mt).toHaveProperty('totalKm')
    expect(mt).toHaveProperty('totalRuns')

    // Leaderboard ordering / filtering.
    expect(d.leaderboard.every((m) => m.totalRuns > 0)).toBe(true)
    expect(d.distanceLeaderboard.every((m) => m.totalKm > 0)).toBe(true)
  })
})

describe('reconciliation sanity check (report-only)', () => {
  it('logs 2025 computed-vs-displayed totals', () => {
    const displayed = {
      totalAttendance: 1025,
      totalKilometers: 10002,
      aaronKm: 947.82,
      aaronRuns: 80,
    }
    const computed = {
      totalAttendanceInstances: data2025.totalAttendanceInstances,
      totalClubKm: data2025.totalClubKm,
      aaronKm: data2025.memberTotals['Aaron']?.totalKm,
      aaronRuns: data2025.memberTotals['Aaron']?.totalRuns,
    }
    // eslint-disable-next-line no-console
    console.log('[2025 reconciliation]', JSON.stringify({ displayed, computed }, null, 2))
    // Sanity floor only; deltas are expected (sheet uses COUNTUNIQUE etc.).
    expect(computed.totalClubKm).toBeGreaterThan(0)
  })
})

describe('birthday metadata below the attendance header', () => {
  // The label can sit in any leading column (Apps Script's listBirthdays accepts
  // all of them). The live sheet puts it in the Date column, which is the shape
  // that once leaked into the totals as a phantom run.
  it.each([
    ['the Date column (live sheet shape)', 'BIRTHDAY,,,,,10-May,,20-Jun'],
    ['a later leading column', ',,,,BIRTHDAY,10-May,,20-Jun'],
  ])('ignores a birthday row labelled in %s', (_, birthdayRow) => {
    const rows = csv2026.split(/\r?\n/)
    const header = rows.findIndex(row => row.startsWith('Date,Meet,Run'))
    expect(header).toBe(10)
    rows.splice(header + 1, 0, birthdayRow)
    expect(parseRunData(rows.join('\n'), 2026)).toEqual(data2026)
  })
})

describe('parseRunData - run dates', () => {
  // Minimal sheet: header plus one row per case. Each row has one attendee, so
  // only the date decides whether it becomes a run.
  const sheet = (...dates) =>
    ['Date,Meet,Run,Approx kms,Actual kms,Ann,Bob,+1\'s', ...dates.map((d) => `"${d}",Filament,Social,8,8,x,,0`)]
      .join('\n')

  it('keeps well-formed dates and reads the weekday from the cell', () => {
    const { runs } = parseRunData(sheet('Fri, 3-Jan', 'Mon, 28-Sep'), 2026)
    expect(runs.map((r) => [r.dayOfWeek, r.parsedDate.getMonth(), r.parsedDate.getDate()])).toEqual([
      ['Fri', 0, 3],
      ['Mon', 8, 28],
    ])
  })

  it('strips sheet footnote markers from the run type', () => {
    const csv = sheet('Mon, 5-Jan').replace('Social', '**Cruise')
    expect(parseRunData(csv, 2026).runs[0].runType).toBe('Cruise')
  })

  it('drops rows whose first cell is not a real run date', () => {
    const { runs, totalRuns } = parseRunData(sheet('Notes', 'Fri, 31-Sep', 'Fri, 3-Sept'), 2026)
    expect(runs).toEqual([])
    expect(totalRuns).toBe(0)
  })
})
