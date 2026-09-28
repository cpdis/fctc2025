import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import Papa from 'papaparse'
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
  it('skips future and empty rows (every run has an attendee or a +1)', () => {
    for (const data of [data2025, data2026]) {
      expect(data.runs.find((r) => r.totalAttendance === 0)).toBeUndefined()
    }
  })

  // Minimal sheet: header plus one row per [date, km, Ann, Bob, +1s] tuple.
  const sheet = (...rows) =>
    [
      "Date,Meet,Run,Approx kms,Actual kms,Ann,Bob,+1's",
      ...rows.map(([date, km, ann, bob, plusOnes]) => `"${date}",Filament,Social,8,${km},${ann},${bob},${plusOnes}`),
    ].join('\n')

  it('drops a dated row with a distance but nobody on it', () => {
    const { runs, totalRuns } = parseRunData(sheet(['Fri, 8-May', '12.5', '', '', '0']), 2026)
    expect(runs).toEqual([])
    expect(totalRuns).toBe(0)
  })

  it('keeps a dated row whose only runners are +1s', () => {
    const { runs } = parseRunData(sheet(['Fri, 8-May', '12.5', '', '', '3']), 2026)
    expect(runs).toHaveLength(1)
    expect(runs[0]).toMatchObject({ attendees: [], plusOnes: 3, totalAttendance: 3 })
  })
})

describe('parseRunData - x-only attendance', () => {
  // One run; Ann's cell holds the value under test, Bob always has "x".
  const sheetWithCell = (cell) =>
    ["Date,Meet,Run,Approx kms,Actual kms,Ann,Bob,+1's", `"Wed, 19-Feb",Filament,Lakes Loop,12.5,12.3,"${cell}",x,0`].join('\n')

  it.each(['x', 'X', ' x ', '  X'])('counts %p as attended', (cell) => {
    const { runs, memberTotals } = parseRunData(sheetWithCell(cell), 2025)
    expect(runs[0].attendance.Ann).toBe(true)
    expect(runs[0].attendees).toEqual(['Ann', 'Bob'])
    expect(memberTotals.Ann.totalRuns).toBe(1)
  })

  it.each(['🛕', 'sad face', '-', '12.30', 'xx', 'y', ''])('does not count %p', (cell) => {
    const { runs, memberTotals } = parseRunData(sheetWithCell(cell), 2025)
    expect(runs[0].attendance.Ann).toBe(false)
    expect(runs[0].attendees).toEqual(['Bob'])
    expect(memberTotals.Ann.totalRuns).toBe(0)
  })
})

describe('parseRunData - member names', () => {
  it('trims header names and normalizes them to NFC', () => {
    // "René" typed with a combining acute (NFD) must match the precomposed "René"
    // the app and the other season use.
    const decomposed = 'René'
    const csv = [
      `Date,Meet,Run,Approx kms,Actual kms, Ann ,${decomposed},+1's`,
      '"Mon, 5-Jan",Drift,Cruise,10,10.4,x,x,0',
    ].join('\n')
    const { members, memberTotals, runs } = parseRunData(csv, 2026)
    expect(members).toEqual(['Ann', 'René'])
    expect(memberTotals['René'].totalRuns).toBe(1)
    expect(runs[0].attendees).toEqual(['Ann', 'René'])
  })
})

// Dated snapshot of the live sheets (27 Sep 2026). Unlike the May fixtures
// above, it carries the 2026 BIRTHDAY row and the 2025 annotation cells ("🛕",
// "sad face"), so it pins the attendance rules against the real sheets.
const snapshotDir = join(import.meta.dirname, '..', '..', 'fixtures', 'attendance', '2026-09-27')
const snapshotCsv = (year) => readFileSync(join(snapshotDir, `${year}.csv`), 'utf-8')

describe('parseRunData - 27 Sep 2026 snapshot', () => {
  const snap2025 = parseRunData(snapshotCsv(2025), 2025)
  const snap2026 = parseRunData(snapshotCsv(2026), 2026)

  it('2026 has 118 runs and Aaron has 89 (AE4: the BIRTHDAY row is not a run)', () => {
    expect(snap2026.totalRuns).toBe(118)
    expect(snap2026.memberTotals.Aaron.totalRuns).toBe(89)
  })

  it('19 Feb 2025 has 16 runners; the "🛕" and "sad face" cells do not count (AE5)', () => {
    const run = snap2025.runs.find((r) => r.id === '2025-02-19-lakes-loop')
    expect(run.attendees).toHaveLength(16)
    expect(run.totalAttendance).toBe(16)
    expect(run.attendance.Adam).toBe(false)
  })

  it('2025 totals drop the annotation cells (AE5)', () => {
    const runs = (name) => snap2025.memberTotals[name].totalRuns
    expect({
      Adam: runs('Adam'),
      'Alex 👑': runs('Alex 👑'),
      Rhys: runs('Rhys'),
      Rohan: runs('Rohan'),
      Toby: runs('Toby'),
    }).toEqual({ Adam: 80, 'Alex 👑': 82, Rhys: 29, Rohan: 8, Toby: 46 })
  })

  it('a blank past row (Fri 8 May 2026) is not a run', () => {
    expect(snap2026.runs.some((r) => r.id.startsWith('2026-05-08'))).toBe(false)
  })

  it('lists the scheduled runs after Fri 25 Sep as upcoming, starting Mon 28 Sep', () => {
    const [next] = snap2026.upcoming
    expect(next).toEqual({
      id: '2026-09-28-intervals',
      parsedDate: new Date(2026, 8, 28),
      dayOfWeek: 'Mon',
      type: 'Intervals',
      event: null,
      location: 'Drift',
      approxKm: 10,
    })
    // Every row from 28 Sep to Wed 30 Dec, and no recorded run moved out.
    expect(snap2026.upcoming).toHaveLength(44)
    expect(snap2026.upcoming.at(-1).id).toBe('2026-12-30-intervals')
    expect(snap2026.totalRuns).toBe(118)
  })

  it('a blank row before the latest run (Fri 8 May) is not upcoming', () => {
    const latest = Math.max(...snap2026.runs.map((r) => r.parsedDate.getTime()))
    expect(snap2026.upcoming.every((row) => row.parsedDate.getTime() > latest)).toBe(true)
    expect(snap2026.upcoming.some((row) => row.id.startsWith('2026-05-08'))).toBe(false)
  })

  it('gives the three Xmas races on Sun 13 Dec their own ids and event', () => {
    const xmas = snap2026.upcoming.filter((row) => row.id.startsWith('2026-12-13'))
    expect(xmas.map((row) => [row.id, row.type, row.event, row.location])).toEqual([
      ['2026-12-13-mara-xmas', 'Marathon', 'Xmas', "Alex 👑's"],
      ['2026-12-13-half-xmas', 'Half Marathon', 'Xmas', "Alex 👑's"],
      ['2026-12-13-10k-xmas', '10K', 'Xmas', "Alex 👑's"],
    ])
  })

  it('a finished season (2025) has nothing upcoming', () => {
    expect(snap2025.upcoming).toEqual([])
  })

  // The row right above the header is the sheet's own per-member run count
  // (column E holds "2026" in the 2026 sheet and is blank in 2025). Every
  // member's parsed total must equal it.
  it.each([
    [2025, snap2025],
    [2026, snap2026],
  ])('every %i member total matches the sheet summary row', (year, data) => {
    const rows = Papa.parse(snapshotCsv(year)).data
    const headerIndex = rows.findIndex((row) => row[0]?.trim() === 'Date' && row.includes('Actual kms'))
    const header = rows[headerIndex]
    const summary = rows[headerIndex - 1]
    const memberCols = header.slice(header.indexOf('Actual kms') + 1, header.indexOf("+1's"))
    expect(memberCols).toHaveLength(data.members.length)

    const sheetTotals = Object.fromEntries(
      memberCols.map((name, i) => [name, Number(summary[header.indexOf('Actual kms') + 1 + i])])
    )
    const parsedTotals = Object.fromEntries(data.members.map((name) => [name, data.memberTotals[name].totalRuns]))
    expect(parsedTotals).toEqual(sheetTotals)
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
    expect(empty.upcoming).toEqual([])
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
    expect(Array.isArray(d.upcoming)).toBe(true)

    // Per-run shape.
    const run = d.runs[0]
    expect(run).toHaveProperty('date')
    expect(run).toHaveProperty('parsedDate')
    expect(run).toHaveProperty('dayOfWeek')
    expect(run).toHaveProperty('id')
    expect(run).toHaveProperty('meet')
    expect(run).toHaveProperty('location')
    expect(run).toHaveProperty('rawRun')
    expect(run).toHaveProperty('runType')
    expect(run).toHaveProperty('type')
    expect(run).toHaveProperty('event')
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

  // [weekday, 0-based month, day] for each run, the fields a date decides.
  const dates = ({ runs }) => runs.map((r) => [r.dayOfWeek, r.parsedDate.getMonth(), r.parsedDate.getDate()])

  it('keeps well-formed dates', () => {
    expect(dates(parseRunData(sheet('Fri, 2-Jan', 'Mon, 28-Sep'), 2026))).toEqual([
      ['Fri', 0, 2],
      ['Mon', 8, 28],
    ])
  })

  // The forms Apps Script's parseSheetDate accepts (apps-script/SheetOps.js),
  // so the web never drops a run the app counts. 2025 dates, as typed.
  it.each([
    ['no comma', 'Sat 4-Oct', ['Sat', 9, 4]],
    ['no weekday', '26-Jan', ['Sun', 0, 26]],
    ['a long weekday', 'Thurs, 2-Oct', ['Thu', 9, 2]],
    ['a long month', 'Thu, 4-Sept', ['Thu', 8, 4]],
    ['a space between day and month', '4 Oct', ['Sat', 9, 4]],
    ['a slash between day and month', 'Sat 4/Oct', ['Sat', 9, 4]],
    ['an upper-case month', 'Sat, 4-OCT', ['Sat', 9, 4]],
  ])('reads a date with %s like Apps Script does', (_, cell, expected) => {
    expect(dates(parseRunData(sheet(cell), 2025))).toEqual([expected])
  })

  it('takes the weekday from the calendar, not the typed text', () => {
    // 5 Jan 2026 is a Monday and 2 Oct 2026 a Friday, whatever the cell says.
    expect(dates(parseRunData(sheet('Tue, 5-Jan-2026', 'Wed, 2-Oct'), 2026))).toEqual([
      ['Mon', 0, 5],
      ['Fri', 9, 2],
    ])
  })

  it('drops rows whose first cell is not a real run date', () => {
    const { runs, totalRuns, upcoming } = parseRunData(
      sheet('Notes', 'BIRTHDAY', 'Fri, 31-Sep', 'Sat, 0-Oct', 'Fri, 3-Foo', ''),
      2026
    )
    expect(runs).toEqual([])
    expect(totalRuns).toBe(0)
    expect(upcoming).toEqual([])
  })
})

describe('parseRunData - run labels, locations and ids', () => {
  // Minimal sheet: header plus one attended row per [date, meet, run] triple.
  const sheet = (...rows) =>
    [
      'Date,Meet,Run,Approx kms,Actual kms,Ann,Bob,+1\'s',
      ...rows.map(([date, meet, run]) => `"${date}",${meet},${run},8,8,x,,0`),
    ].join('\n')

  it('stamps the normalized type, event and location, and keeps the sheet labels for Wrapped', () => {
    const [run] = parseRunData(sheet(['Sun, 13-Dec', 'Some-day', 'Half - Xmas']), 2026).runs
    expect(run).toMatchObject({
      id: '2026-12-13-half-xmas',
      type: 'Half Marathon',
      event: 'Xmas',
      location: 'Someday',
      rawRun: 'Half - Xmas',
      runType: 'Half - Xmas',
      meet: 'Some-day',
    })
  })

  it('strips sheet footnote markers so "**Cruise" groups with "Cruise"', () => {
    const { runs, runsByType } = parseRunData(
      sheet(['Mon, 5-Jan', 'Drift', '**Cruise'], ['Mon, 12-Jan', 'Drift', 'Cruise']),
      2026
    )
    expect(runs.map((r) => [r.rawRun, r.runType, r.type, r.event])).toEqual([
      ['**Cruise', 'Cruise', 'Cruise', null],
      ['Cruise', 'Cruise', 'Cruise', null],
    ])
    expect(Object.keys(runsByType)).toEqual(['Cruise'])
    expect(runsByType.Cruise.count).toBe(2)
  })

  it('keys runsByLocation by the normalized location', () => {
    const { runsByLocation } = parseRunData(
      sheet(['Wed, 7-Jan', 'Some-day', 'Hills'], ['Wed, 14-Jan', ' Someday ', 'Hills']),
      2026
    )
    expect(Object.keys(runsByLocation)).toEqual(['Someday'])
    expect(runsByLocation.Someday.count).toBe(2)
  })

  it('gives a repeated date and label a suffixed id in sheet order', () => {
    const { runs } = parseRunData(
      sheet(['Fri, 25-Sep', 'MSBB', 'River Loop'], ['Fri, 25-Sep', 'MSBB', 'River Loop']),
      2026
    )
    expect(runs.map((r) => r.id)).toEqual(['2026-09-25-river-loop', '2026-09-25-river-loop-2'])
  })

  it('gives every 2026 fixture run a unique id and one Cruise key', () => {
    const ids = data2026.runs.map((r) => r.id)
    expect(ids.every((id) => /^2026-\d{2}-\d{2}-[a-z0-9-]+$/.test(id))).toBe(true)
    expect(new Set(ids).size).toBe(ids.length)
    expect(Object.keys(data2026.runsByType).filter((t) => t.includes('Cruise'))).toEqual(['Cruise'])
  })

  it('keeps ids unique when seasons merge into All time', () => {
    const ids = combineYearData([data2025, data2026]).runs.map((r) => r.id)
    expect(new Set(ids).size).toBe(ids.length)
  })
})

describe('parseRunData - upcoming runs', () => {
  // Minimal sheet: header plus one row per [date, run, actual km, Ann, +1s].
  const sheet = (...rows) =>
    [
      "Date,Meet,Run,Approx kms,Actual kms,Ann,+1's",
      ...rows.map(([date, run, km, ann, plusOnes]) => `"${date}",Filament,${run},8,${km},${ann},${plusOnes}`),
    ].join('\n')

  it('before the first run, every scheduled row is upcoming, in date order', () => {
    const { runs, upcoming } = parseRunData(sheet(['Fri, 9-Jan', 'Social', '', '', '0'], ['Wed, 7-Jan', 'Social', '', '', '0']), 2026)
    expect(runs).toEqual([])
    expect(upcoming.map((row) => row.id)).toEqual(['2026-01-07-social', '2026-01-09-social'])
  })

  it('a scheduled row keeps its id once it is recorded', () => {
    const before = parseRunData(sheet(['Mon, 5-Jan', 'Cruise', '', '', '0']), 2026)
    const after = parseRunData(sheet(['Mon, 5-Jan', 'Cruise', '10.2', 'x', '0']), 2026)
    expect(before.upcoming[0].id).toBe(after.runs[0].id)
    expect(after.upcoming).toEqual([])
  })

  // Two Intervals rows on Fri 25 Sep. Recording the first one later must not
  // move the second run's id, or a saved link would open another run.
  it('recording an earlier same-date, same-label row keeps the later run id', () => {
    const secondOnly = parseRunData(
      sheet(['Fri, 25-Sep', 'Intervals', '', '', '0'], ['Fri, 25-Sep', 'Intervals', '8', 'x', '0']),
      2026
    )
    const both = parseRunData(
      sheet(['Fri, 25-Sep', 'Intervals', '8', 'x', '0'], ['Fri, 25-Sep', 'Intervals', '8', 'x', '0']),
      2026
    )
    expect(secondOnly.runs.map((run) => run.id)).toEqual(['2026-09-25-intervals-2'])
    expect(both.runs.map((run) => run.id)).toEqual(['2026-09-25-intervals', '2026-09-25-intervals-2'])
    // The blank first row is on the latest run's date, so it is not upcoming.
    expect(secondOnly.upcoming).toEqual([])
  })

  it('numbers same-date, same-label rows in sheet order across runs and upcoming', () => {
    const { runs, upcoming } = parseRunData(
      sheet(
        ['Mon, 28-Sep', 'Intervals', '8', 'x', '0'],
        ['Wed, 30-Sep', 'Social', '', '', '0'],
        ['Wed, 30-Sep', 'Social', '', '', '0']
      ),
      2026
    )
    expect(runs.map((run) => run.id)).toEqual(['2026-09-28-intervals'])
    expect(upcoming.map((row) => row.id)).toEqual(['2026-09-30-social', '2026-09-30-social-2'])
  })

  it('All time keeps only rows after the latest run of every season', () => {
    // 2025 stopped a week early, so its blank 10 Jan row is stale by 2026.
    const early = parseRunData(sheet(['Fri, 3-Jan', 'Social', '8', 'x', '0'], ['Fri, 10-Jan', 'Social', '', '', '0']), 2025)
    const later = parseRunData(sheet(['Mon, 5-Jan', 'Cruise', '10', 'x', '0'], ['Wed, 7-Jan', 'Social', '', '', '0']), 2026)
    expect(early.upcoming.map((row) => row.id)).toEqual(['2025-01-10-social'])
    expect(combineYearData([later, early]).upcoming.map((row) => row.id)).toEqual(['2026-01-07-social'])
  })
})
