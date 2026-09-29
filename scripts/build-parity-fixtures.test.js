// @vitest-environment node
import { describe, it, expect } from 'vitest'
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import Papa from 'papaparse'
import {
  PARITY_DIR,
  SNAPSHOT_DIR,
  buildParityFiles,
  buildParityFixture,
  formatFixture,
} from './build-parity-fixtures.js'

// One in-memory rebuild shared by every test; the committed files are read per test.
const built = buildParityFiles()
const committed = (season) => readFileSync(join(PARITY_DIR, `${season}.json`), 'utf8')
const fixture = Object.fromEntries(built.map(({ season, content }) => [season, JSON.parse(content)]))

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
/** Calendar weekday of an ISO date, read as a local date like the parser does. */
const weekdayOf = (iso) => {
  const [y, m, d] = iso.split('-').map(Number)
  return WEEKDAYS[new Date(y, m - 1, d).getDay()]
}
const roundKm = (km) => Math.round(km * 100) / 100

describe('committed parity fixtures', () => {
  it('cover every season in the snapshot and nothing else', () => {
    expect(built.map(({ season }) => season)).toEqual([2025, 2026])
    expect(readdirSync(PARITY_DIR).sort()).toEqual(['2025.json', '2026.json'])
  })

  it.each(built)('parity/$season.json equals a fresh build (rerun the script if this fails)', ({ season, content }) => {
    // Structural diff first (readable on failure), then byte equality (format and key order).
    expect(JSON.parse(committed(season))).toEqual(JSON.parse(content))
    expect(committed(season)).toBe(content)
  })
})

describe.each([2025, 2026])('%s runs', (season) => {
  const { runs } = fixture[season]

  it('each carry an id, ISO date, calendar weekday, raw labels and normalized fields', () => {
    for (const run of runs) {
      expect(run.date).toMatch(/^\d{4}-\d{2}-\d{2}$/)
      expect(run.date.startsWith(`${season}-`)).toBe(true)
      expect(run.weekday).toBe(weekdayOf(run.date))
      expect(run.id.startsWith(`${run.date}-`)).toBe(true)
      expect(typeof run.run).toBe('string')
      expect(typeof run.meet).toBe('string')
      expect(run.type).toBeTruthy()
      expect(run.location).toBeTruthy()
      expect(typeof run.actualKm).toBe('number')
    }
    expect(new Set(runs.map((run) => run.id)).size).toBe(runs.length)
  })

  it('are in date order, attendees sorted, and every run has someone on it', () => {
    const dates = runs.map((run) => run.date)
    expect(dates).toEqual([...dates].sort())
    for (const run of runs) {
      expect(run.attendees).toEqual([...run.attendees].sort())
      expect(run.attendees.length + run.plusOnes).toBeGreaterThan(0)
    }
  })
})

describe('raw labels', () => {
  it('keep the sheet cell as typed beside the normalized fields', () => {
    const cruise = fixture[2026].runs.find((run) => run.id === '2026-01-05-cruise')
    expect(cruise).toMatchObject({ run: '**Cruise', type: 'Cruise', event: null })

    const someday = fixture[2026].runs.find((run) => run.meet === 'Some-day')
    expect(someday.location).toBe('Someday')

    const invasionDay = fixture[2025].runs.filter((run) => run.date === '2025-01-27')
    expect(invasionDay.map(({ run, type, event }) => [run, type, event])).toEqual([
      ['Half- Invasion Day', 'Half Marathon', 'Invasion Day'],
      ['10k- Invasion Day', '10K', 'Invasion Day'],
    ])
  })
})

describe('2026 snapshot cut-off', () => {
  it('stops at the last recorded run although the sheet lists planned rows to December', () => {
    const csv = readFileSync(join(SNAPSHOT_DIR, '2026.csv'), 'utf8')
    // The sheet already holds the unrecorded Monday after the snapshot date.
    expect(csv).toContain('"Mon, 28-Sep",Drift,Intervals')
    const { runs } = fixture[2026]
    expect(runs.at(-1).date).toBe('2026-09-25')
    expect(runs.every((run) => run.date <= '2026-09-25')).toBe(true)
  })
})

describe('expected block', () => {
  it('matches the acceptance examples', () => {
    const { expected: e2025, runs: runs2025 } = fixture[2025]
    const { expected: e2026 } = fixture[2026]
    const streak = (expected, name) => expected.streaks.find((s) => s.name === name)
    const member = (expected, name) => expected.members.find((m) => m.name === name)

    // AE1: Aaron's 2026 streak.
    expect(streak(e2026, 'Aaron')).toMatchObject({ current: 14, currentFrom: '2026-08-26' })
    // AE4: 118 runs in 2026, 89 for Aaron.
    expect(e2026.totals.runs).toBe(118)
    expect(member(e2026, 'Aaron').runs).toBe(89)
    // AE5: 16 runners on 19 Feb 2025, 80 runs for Adam.
    expect(runs2025.find((run) => run.date === '2025-02-19').attendees).toHaveLength(16)
    expect(member(e2025, 'Adam').runs).toBe(80)
    // AE9: 104 club days in 2025, Scott best 54 (3 Jan to 9 Jul), ends on 49.
    expect(e2025.clubDays.count).toBe(104)
    expect(streak(e2025, 'Scott')).toMatchObject({
      current: 49,
      best: 54,
      bestFrom: '2025-01-03',
      bestTo: '2025-07-09',
    })
    expect(e2025.clubDays.dates).not.toContain('2025-01-27')
  })

  it.each([2025, 2026])('%s totals recompute from the runs alone, as the Swift test does', (season) => {
    const { runs, expected } = fixture[season]
    const names = [...new Set(runs.flatMap((run) => run.attendees))].sort()

    expect(expected.totals).toEqual({
      runs: runs.length,
      memberKm: roundKm(runs.reduce((sum, run) => sum + run.actualKm * run.attendees.length, 0)),
      runners: names.length,
    })
    expect(expected.members.map((m) => m.name)).toEqual(names)
    expect(expected.streaks.map((s) => s.name)).toEqual(names)
    for (const { name, runs: count, memberKm } of expected.members) {
      const ran = runs.filter((run) => run.attendees.includes(name))
      expect(count).toBe(ran.length)
      expect(memberKm).toBe(roundKm(ran.reduce((sum, run) => sum + run.actualKm, 0)))
    }
  })

  it.each([2025, 2026])('%s club days are run dates on the season weekdays, in order', (season) => {
    const { runs, clubWeekdays, expected } = fixture[season]
    const runDates = new Set(runs.map((run) => run.date))
    expect(clubWeekdays).toEqual(season === 2025 ? ['Wed', 'Fri'] : ['Mon', 'Wed', 'Fri'])
    expect(expected.clubDays.dates).toHaveLength(expected.clubDays.count)
    expect(expected.clubDays.dates).toEqual([...expected.clubDays.dates].sort())
    for (const date of expected.clubDays.dates) {
      expect(runDates.has(date)).toBe(true)
      expect(clubWeekdays).toContain(weekdayOf(date))
    }
    for (const { date } of runs) {
      if (clubWeekdays.includes(weekdayOf(date))) expect(expected.clubDays.dates).toContain(date)
    }
  })

  it.each([2025, 2026])('%s milestones come from the season totals', (season) => {
    const { expected } = fixture[season]
    const runsOf = Object.fromEntries(expected.members.map((m) => [m.name, m.runs]))
    for (const entry of expected.milestones) {
      expect(entry.runs).toBe(runsOf[entry.name])
      expect(entry.milestone % 50).toBe(0)
      expect(entry.runsNeeded).toBe(entry.milestone - entry.runs)
      expect(entry.runsNeeded).toBeLessThanOrEqual(10)
    }
  })

  // The sheet's own summary rows sit above the header: per-member runs on the
  // row right above it (both seasons), per-member km two rows up in 2025 (2
  // decimals) and four rows up in 2026 (whole km).
  it.each([
    { season: 2025, kmRowsUp: 2, kmDecimals: 2 },
    { season: 2026, kmRowsUp: 4, kmDecimals: 0 },
  ])('$season member totals agree with the sheet summary rows', ({ season, kmRowsUp, kmDecimals }) => {
    const rows = Papa.parse(readFileSync(join(SNAPSHOT_DIR, `${season}.csv`), 'utf8')).data
    const headerIndex = rows.findIndex((row) => row[0]?.trim() === 'Date')
    const header = rows[headerIndex].map((cell) => cell.trim().normalize('NFC'))
    const cell = (rowsUp, name) => Number(rows[headerIndex - rowsUp][header.indexOf(name)])
    // Half a unit of the sheet's rounding, plus the fixture's own 2-decimal rounding.
    const tolerance = 0.5 * 10 ** -kmDecimals + 0.005

    for (const { name, runs, memberKm } of fixture[season].expected.members) {
      expect(runs, name).toBe(cell(1, name))
      expect(Math.abs(memberKm - cell(kmRowsUp, name)), name).toBeLessThanOrEqual(tolerance)
    }
  })
})

describe('buildParityFixture - synthetic sheet', () => {
  // Out of date order on purpose; Zed's column comes before Ann's.
  const csv = [
    "Date,Meet,Run,Approx kms,Actual kms,Zed,Ann,+1's",
    '"Wed, 7-Jan",Filament,Social,8,8,x,x,0',
    '"Mon, 5-Jan",Drift,**Cruise,10,10.5,,X,1',
    '"Mon, 5-Jan",Drift,Hills,10,5,x,,0',
    '"Sat, 10-Jan",Pub,Pub Run,5,5,,,2',
    '"Mon, 12-Jan",Drift,Intervals,10,,,,0',
  ].join('\n')
  const synthetic = buildParityFixture(csv, 2026)

  it('sorts runs by date then sheet order, sorts attendees and drops unrecorded rows', () => {
    expect(synthetic.runs.map(({ id, run, attendees, plusOnes }) => [id, run, attendees, plusOnes])).toEqual([
      ['2026-01-05-cruise', '**Cruise', ['Ann'], 1],
      ['2026-01-05-hills', 'Hills', ['Zed'], 0],
      ['2026-01-07-social', 'Social', ['Ann', 'Zed'], 0],
      ['2026-01-10-pub-run', 'Pub Run', [], 2],
    ])
  })

  it('computes totals without +1s, club days, streaks and an empty shortlist', () => {
    expect(synthetic.expected).toEqual({
      totals: { runs: 4, memberKm: 31.5, runners: 2 },
      members: [
        { name: 'Ann', runs: 2, memberKm: 18.5 },
        { name: 'Zed', runs: 2, memberKm: 13 },
      ],
      clubDays: { count: 2, dates: ['2026-01-05', '2026-01-07'] },
      streaks: ['Ann', 'Zed'].map((name) => ({
        name,
        current: 2,
        currentFrom: '2026-01-05',
        best: 2,
        bestFrom: '2026-01-05',
        bestTo: '2026-01-07',
        madeByWeekday: { Mon: 1, Wed: 1 },
      })),
      milestones: [],
    })
  })

  it('keeps keys in a fixed order so committed diffs stay small', () => {
    expect(Object.keys(synthetic)).toEqual(['season', 'clubWeekdays', 'runs', 'expected'])
    expect(Object.keys(synthetic.runs[0])).toEqual([
      'id', 'date', 'weekday', 'run', 'meet', 'type', 'event', 'location', 'actualKm', 'attendees', 'plusOnes',
    ])
    expect(Object.keys(synthetic.expected)).toEqual(['totals', 'members', 'clubDays', 'streaks', 'milestones'])
    expect(formatFixture(synthetic).endsWith('}\n')).toBe(true)
    expect(formatFixture(synthetic)).toContain('\n  "season": 2026,\n')
  })

  it('fails loudly on a sheet without a header row', () => {
    expect(() => buildParityFixture('Notes:,,\n"Fri, 2-Jan",Il Lido,Soft Sand', 2026)).toThrow(/header row/)
  })
})
