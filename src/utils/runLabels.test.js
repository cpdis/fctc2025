import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { normalizeLocation, parseRunLabel, runId, shortMonthName } from './runLabels'
import { parseRunData } from './dataParser'

describe('parseRunLabel - races', () => {
  it.each([
    ['Half - Xmas', 'Half Marathon', 'Xmas'],
    ['Half- Invasion Day', 'Half Marathon', 'Invasion Day'],
    ['Half - Anzac Day', 'Half Marathon', 'Anzac Day'],
    ['Half- Beer Run', 'Half Marathon', 'Beer Run'],
    ['Mara- Anzac Day', 'Marathon', 'Anzac Day'],
    ['Mara - Xmas', 'Marathon', 'Xmas'],
    ['10k - Xmas', '10K', 'Xmas'],
    ['10k- Invasion Day', '10K', 'Invasion Day'],
    ['10K -Xmas', '10K', 'Xmas'],
    ['  HALF  -  Xmas  ', 'Half Marathon', 'Xmas'],
  ])('"%s" is %s with event %s', (raw, type, event) => {
    expect(parseRunLabel(raw)).toMatchObject({ type, event })
  })

  it('keeps the clean label as typed for Wrapped', () => {
    expect(parseRunLabel('Half- Invasion Day').label).toBe('Half- Invasion Day')
  })
})

describe('parseRunLabel - named runs', () => {
  it.each([
    ['N/hood Loop', "N'hood Loop", null],
    ['FILAMENT CUP 🏆', 'Filament Cup', null],
    ['Filament Cup 🏆', 'Filament Cup', null],
    ['Good Fri Pancake', 'Pancake Run', 'Good Friday'],
    ['Intervals', 'Intervals', null],
    ['Pub Run', 'Pub Run', null],
    ['Kings Park', 'Kings Park', null],
    [' Soft Sand ', 'Soft Sand', null],
  ])('"%s" is %s', (raw, type, event) => {
    expect(parseRunLabel(raw)).toMatchObject({ type, event })
  })

  it('does not read a label that only starts with a race word as a race', () => {
    expect(parseRunLabel('Halfway Hills')).toEqual({ label: 'Halfway Hills', type: 'Halfway Hills', event: null })
  })

  it('gives a blank label the Other type', () => {
    expect(parseRunLabel('')).toEqual({ label: '', type: 'Other', event: null })
    expect(parseRunLabel(undefined)).toEqual({ label: '', type: 'Other', event: null })
    expect(parseRunLabel('**')).toEqual({ label: '', type: 'Other', event: null })
  })
})

describe('parseRunLabel - footnote markers', () => {
  it('"**Cruise" is Cruise with no event, the same type as "Cruise"', () => {
    expect(parseRunLabel('**Cruise')).toEqual({ label: 'Cruise', type: 'Cruise', event: null })
    expect(parseRunLabel('Cruise').type).toBe(parseRunLabel('**Cruise').type)
  })

  it('strips trailing markers and markers on a race label', () => {
    expect(parseRunLabel('Cruise**').type).toBe('Cruise')
    expect(parseRunLabel('**Half - Xmas')).toEqual({ label: 'Half - Xmas', type: 'Half Marathon', event: 'Xmas' })
  })
})

describe('normalizeLocation', () => {
  it('"Some-day" and "Someday" give the same location', () => {
    expect(normalizeLocation('Some-day')).toBe('Someday')
    expect(normalizeLocation('Someday')).toBe('Someday')
  })

  it('passes unknown locations through trimmed', () => {
    expect(normalizeLocation(' Drift ')).toBe('Drift')
    expect(normalizeLocation("Alex 👑's")).toBe("Alex 👑's")
    expect(normalizeLocation('TBC')).toBe('TBC')
  })

  it('gives a blank cell an empty location', () => {
    expect(normalizeLocation(undefined)).toBe('')
    expect(normalizeLocation('  ')).toBe('')
  })
})

describe('runId', () => {
  const fri25Sep = new Date(2026, 8, 25)
  const sun13Dec = new Date(2026, 11, 13)

  it('is the local date plus the slug of the label', () => {
    expect(runId(fri25Sep, 'River Loop')).toBe('2026-09-25-river-loop')
    expect(runId(new Date(2026, 0, 5), '**Cruise')).toBe('2026-01-05-cruise')
    expect(runId(new Date(2025, 3, 18), 'FILAMENT CUP 🏆')).toBe('2025-04-18-filament-cup')
    expect(runId(new Date(2025, 0, 8), 'N/hood Loop')).toBe('2025-01-08-n-hood-loop')
  })

  it('gives the three Xmas races on one day distinct ids by label', () => {
    const taken = new Set()
    const ids = ['Mara - Xmas', 'Half - Xmas', '10k - Xmas'].map((label) => runId(sun13Dec, label, taken))
    expect(ids).toEqual(['2026-12-13-mara-xmas', '2026-12-13-half-xmas', '2026-12-13-10k-xmas'])
  })

  it('suffixes a forced collision with -2, then -3', () => {
    const taken = new Set()
    expect(runId(fri25Sep, 'River Loop', taken)).toBe('2026-09-25-river-loop')
    expect(runId(fri25Sep, 'River Loop', taken)).toBe('2026-09-25-river-loop-2')
    expect(runId(fri25Sep, 'River Loop', taken)).toBe('2026-09-25-river-loop-3')
    // "**Cruise" and "Cruise" slug the same, so they collide too.
    expect(runId(fri25Sep, '**Cruise', taken)).toBe('2026-09-25-cruise')
    expect(runId(fri25Sep, 'Cruise', taken)).toBe('2026-09-25-cruise-2')
  })

  it('falls back to "run" when the label has nothing to slug', () => {
    expect(runId(fri25Sep, '')).toBe('2026-09-25-run')
    expect(runId(fri25Sep, '🏆')).toBe('2026-09-25-run')
  })

  it('folds accents into ASCII', () => {
    expect(runId(fri25Sep, 'Café Loop')).toBe('2026-09-25-cafe-loop')
  })
})

// The published season sheets. When a new spelling shows up, this fails: add
// it to the alias tables in runLabels.js (and the Swift RunLabel) or, for a
// genuinely new kind of run, to KNOWN_TYPES here.
describe('the public season sheets', () => {
  const KNOWN_TYPES = [
    '10K',
    'Cruise',
    'Filament Cup',
    'Half Marathon',
    'Hills',
    'Intervals',
    'Kings Park',
    'Lakes Loop',
    'Marathon',
    "N'hood Loop",
    'Pancake Run',
    'Pub Run',
    'River Loop',
    'Social',
    'Soft Sand',
  ]
  const dataDir = join(import.meta.dirname, '..', '..', 'public', 'data')
  const runs = [2025, 2026].flatMap(
    (year) => parseRunData(readFileSync(join(dataDir, `${year}.csv`), 'utf-8'), year).runs
  )

  it('gives every run a unique id', () => {
    const ids = runs.map((r) => r.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it('gives every run a type from the known list', () => {
    const unknown = [...new Set(runs.map((r) => r.type))].filter((t) => !KNOWN_TYPES.includes(t))
    expect(unknown).toEqual([])
  })

  it('never keeps a footnote marker or a "Some-day" spelling', () => {
    expect(runs.filter((r) => r.runType.includes('*') || r.type.includes('*'))).toEqual([])
    expect(runs.filter((r) => r.location === 'Some-day')).toEqual([])
  })
})

describe('shortMonthName', () => {
  it('reads each month exactly as toLocaleString does', () => {
    for (let month = 0; month < 12; month++) {
      const date = new Date(2026, month, 15)
      expect(shortMonthName(date)).toBe(date.toLocaleString('default', { month: 'short' }))
    }
  })
})
