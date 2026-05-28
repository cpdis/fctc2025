import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from './dataParser'

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
