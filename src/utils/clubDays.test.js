import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { buildClubDays, memberClubDays, milestoneShortlist, nextMilestone } from './clubDays'
import { parseRunData } from './dataParser'

// Dated snapshot of the live sheets (27 Sep 2026): the 2026 BIRTHDAY row and
// the 2025 annotation cells are both present.
const snapshotDir = join(import.meta.dirname, '..', '..', 'fixtures', 'attendance', '2026-09-27')
const snapshot = (year) => parseRunData(readFileSync(join(snapshotDir, `${year}.csv`), 'utf-8'), year)
const snap2025 = snapshot(2025)
const snap2026 = snapshot(2026)

const days2025 = buildClubDays(snap2025.runs)
const days2026 = buildClubDays(snap2026.runs)
const daysAllTime = buildClubDays([...snap2025.runs, ...snap2026.runs])

/** A minimal run: only the fields the club-day rules read. */
const run = (iso, weekday, attendees) => {
  const [y, m, d] = iso.split('-').map(Number)
  return { parsedDate: new Date(y, m - 1, d), dayOfWeek: weekday, attendees }
}

describe('buildClubDays - synthetic runs', () => {
  const everyDay = () => ['Mon', 'Wed', 'Fri']

  it('orders club days by date whatever order the runs arrive in', () => {
    const days = buildClubDays(
      [run('2026-01-09', 'Fri', ['Ann']), run('2026-01-05', 'Mon', ['Bob']), run('2026-01-07', 'Wed', ['Ann'])],
      everyDay
    )
    expect(days.map((d) => [d.date, d.weekday])).toEqual([
      ['2026-01-05', 'Mon'],
      ['2026-01-07', 'Wed'],
      ['2026-01-09', 'Fri'],
    ])
  })

  it('folds same-date runs into one club day that anyone on either run made', () => {
    const half = run('2026-01-26', 'Mon', ['Ann'])
    const tenK = run('2026-01-26', 'Mon', ['Bob'])
    const [day] = buildClubDays([half, tenK], everyDay)
    expect(day.runs).toEqual([half, tenK])
    expect([...day.attendees]).toEqual(['Ann', 'Bob'])
  })

  it('leaves out runs on other weekdays, using the weekdays it is given', () => {
    const runs = [run('2025-01-27', 'Mon', ['Ann']), run('2025-01-29', 'Wed', ['Ann']), run('2025-02-01', 'Sat', ['Ann'])]
    expect(buildClubDays(runs, () => ['Wed', 'Fri']).map((d) => d.date)).toEqual(['2025-01-29'])
    expect(buildClubDays(runs, () => ['Mon', 'Wed', 'Fri']).map((d) => d.date)).toEqual(['2025-01-27', '2025-01-29'])
  })

  it('asks for each run season’s own weekdays', () => {
    const seen = []
    const weekdaysFor = (year) => {
      seen.push(year)
      return year === 2025 ? ['Wed', 'Fri'] : ['Mon', 'Wed', 'Fri']
    }
    const days = buildClubDays([run('2025-12-29', 'Mon', ['Ann']), run('2026-01-05', 'Mon', ['Ann'])], weekdaysFor)
    expect(days.map((d) => d.date)).toEqual(['2026-01-05'])
    expect(new Set(seen)).toEqual(new Set([2025, 2026]))
  })

  it('returns no club days for no runs', () => {
    expect(buildClubDays([], everyDay)).toEqual([])
    expect(buildClubDays(undefined, everyDay)).toEqual([])
  })
})

describe('memberClubDays - synthetic club days', () => {
  const days = buildClubDays(
    [
      run('2026-01-05', 'Mon', ['Ann', 'Bob']),
      run('2026-01-07', 'Wed', ['Ann', 'Bob']),
      run('2026-01-09', 'Fri', ['Bob']),
      run('2026-01-12', 'Mon', ['Ann', 'Bob']),
      run('2026-01-14', 'Wed', ['Ann']),
      run('2026-01-16', 'Fri', ['Ann']),
    ],
    () => ['Mon', 'Wed', 'Fri']
  )

  it('counts the current streak back from the latest club day', () => {
    expect(memberClubDays(days, 'Ann')).toMatchObject({ current: 3, currentFrom: '2026-01-12' })
  })

  it('has no current streak when the member missed the latest club day', () => {
    expect(memberClubDays(days, 'Bob')).toMatchObject({ current: 0, currentFrom: null })
  })

  it('keeps the earliest of two equally long best streaks', () => {
    // Ann made 5-7 Jan (2) and 12-16 Jan (3); Bob made 5-12 Jan (4).
    expect(memberClubDays(days, 'Ann')).toMatchObject({ best: 3, bestFrom: '2026-01-12', bestTo: '2026-01-16' })
    expect(memberClubDays(days, 'Bob')).toMatchObject({ best: 4, bestFrom: '2026-01-05', bestTo: '2026-01-12' })

    const tied = buildClubDays(
      [run('2026-01-05', 'Mon', ['Cy']), run('2026-01-07', 'Wed', []), run('2026-01-09', 'Fri', ['Cy'])],
      () => ['Mon', 'Wed', 'Fri']
    )
    expect(memberClubDays(tied, 'Cy')).toMatchObject({ best: 1, bestFrom: '2026-01-05', bestTo: '2026-01-05' })
  })

  it('counts club days made per weekday, in weekday order, zero included', () => {
    expect(memberClubDays(days, 'Ann')).toMatchObject({ made: 5, madeByWeekday: { Mon: 2, Wed: 2, Fri: 1 } })
    expect(Object.keys(memberClubDays(days, 'Ann').madeByWeekday)).toEqual(['Mon', 'Wed', 'Fri'])
    expect(memberClubDays(days, 'Nobody')).toEqual({
      made: 0,
      madeByWeekday: { Mon: 0, Wed: 0, Fri: 0 },
      current: 0,
      currentFrom: null,
      best: 0,
      bestFrom: null,
      bestTo: null,
    })
  })

  it('handles a season with no club days yet', () => {
    expect(memberClubDays([], 'Ann')).toEqual({
      made: 0,
      madeByWeekday: {},
      current: 0,
      currentFrom: null,
      best: 0,
      bestFrom: null,
      bestTo: null,
    })
  })
})

describe('club days - 27 Sep 2026 snapshot', () => {
  it('Aaron’s 2026 current streak is 14 from Wed 26 Aug (AE1)', () => {
    expect(memberClubDays(days2026, 'Aaron')).toMatchObject({ current: 14, currentFrom: '2026-08-26' })
    expect(days2026.at(-1).date).toBe('2026-09-25')
  })

  it('the Sat 5 Sep Pub Run neither adds to nor breaks a streak (AE1)', () => {
    const pubRun = snap2026.runs.find((r) => r.id === '2026-09-05-pub-run')
    expect(pubRun.attendees).toContain('Aaron')
    expect(days2026.some((d) => d.date === '2026-09-05')).toBe(false)

    // Take Aaron off the Pub Run: the streak does not change.
    const withoutAaron = snap2026.runs.map((r) =>
      r === pubRun ? { ...r, attendees: r.attendees.filter((name) => name !== 'Aaron') } : r
    )
    expect(memberClubDays(buildClubDays(withoutAaron), 'Aaron')).toMatchObject({ current: 14, currentFrom: '2026-08-26' })
  })

  it('a member who ran only the Mon 26 Jan 2026 10k made that club day (AE2)', () => {
    const day = days2026.find((d) => d.date === '2026-01-26')
    expect(day.runs.map((r) => r.type)).toEqual(['Half Marathon', '10K'])
    const [half, tenK] = day.runs
    expect(half.attendees).not.toContain('Alex B')
    expect(tenK.attendees).toContain('Alex B')
    expect(day.attendees.has('Alex B')).toBe(true)
  })

  it('skipping the Sun 13 Dec Xmas specials leaves a streak unchanged (AE3)', () => {
    // The Xmas rows are still blank in the snapshot; record them for someone else.
    const xmas = ['Marathon', 'Half Marathon', '10K'].map((type) => ({
      ...run('2026-12-13', 'Sun', ['Alex 👑']),
      type,
    }))
    const days = buildClubDays([...snap2026.runs, ...xmas])
    expect(days.some((d) => d.date === '2026-12-13')).toBe(false)
    expect(memberClubDays(days, 'Aaron')).toMatchObject({ current: 14, currentFrom: '2026-08-26' })
  })

  it('2025 has 104 club days and the Invasion Day Monday runs are specials (AE9)', () => {
    expect(days2025).toHaveLength(104)
    expect(days2025.some((d) => d.weekday === 'Mon')).toBe(false)
    expect(snap2025.runs.filter((r) => r.id.startsWith('2025-01-27'))).toHaveLength(2)
    expect(days2025.some((d) => d.date === '2025-01-27')).toBe(false)
  })

  it('Scott’s 2025 best streak is 54 (3 Jan to 9 Jul) and he ends the season on 49 (AE9)', () => {
    expect(memberClubDays(days2025, 'Scott')).toMatchObject({
      best: 54,
      bestFrom: '2025-01-03',
      bestTo: '2025-07-09',
      current: 49,
    })
  })

  it('a blank past row (Fri 8 May 2026) is not a club day', () => {
    expect(days2026.some((d) => d.date === '2026-05-08')).toBe(false)
  })

  it('All time keeps each season’s own club weekdays', () => {
    expect(daysAllTime).toHaveLength(days2025.length + days2026.length)
    expect(daysAllTime.some((d) => d.date === '2025-01-27')).toBe(false)
    expect(daysAllTime.some((d) => d.date === '2026-01-26')).toBe(true)
  })

  it('All time: a streak running to Wed 31 Dec 2025 continues into Fri 2 Jan 2026', () => {
    const boundary = daysAllTime.findIndex((d) => d.date === '2025-12-31')
    expect(daysAllTime[boundary + 1].date).toBe('2026-01-02')

    const endOf2025 = memberClubDays(days2025, 'Adam')
    expect(endOf2025.current).toBeGreaterThan(0)
    const through2Jan = memberClubDays(daysAllTime.slice(0, boundary + 2), 'Adam')
    expect(through2Jan).toMatchObject({ current: endOf2025.current + 1, currentFrom: endOf2025.currentFrom })
  })
})

describe('milestoneShortlist', () => {
  const totals = (entries) => Object.entries(entries).map(([name, runs]) => ({ name, runs }))

  it('the next milestone is the next multiple of 50, even from a landmark', () => {
    expect(nextMilestone(0)).toBe(50)
    expect(nextMilestone(49)).toBe(50)
    expect(nextMilestone(50)).toBe(100)
    expect(nextMilestone(143)).toBe(150)
  })

  it('lists members 10 or fewer runs away, closest first', () => {
    expect(milestoneShortlist(totals({ Ann: 45, Bob: 48, Cy: 39, Di: 40 }))).toEqual([
      { name: 'Bob', runs: 48, milestone: 50, runsNeeded: 2 },
      { name: 'Ann', runs: 45, milestone: 50, runsNeeded: 5 },
      { name: 'Di', runs: 40, milestone: 50, runsNeeded: 10 },
    ])
  })

  it('leaves out a member sitting on a landmark and one who never ran', () => {
    expect(milestoneShortlist(totals({ Ann: 100, Bob: 0, Cy: 50 }))).toEqual([])
  })

  it('shows the top 3 plus anyone tied with third', () => {
    const shortlist = milestoneShortlist(totals({ Ann: 48, Bob: 47, Cy: 45, Di: 95, Ed: 44, Flo: 145 }))
    expect(shortlist.map((c) => [c.name, c.runsNeeded])).toEqual([
      ['Ann', 2],
      ['Bob', 3],
      ['Cy', 5],
      ['Di', 5],
      ['Flo', 5],
    ])
  })

  it('breaks a tie by name so the order is stable', () => {
    expect(milestoneShortlist(totals({ Zed: 98, Amy: 48 })).map((c) => c.name)).toEqual(['Amy', 'Zed'])
  })

  it('on the 27 Sep 2026 all-time totals it returns Col, Claire and Adam', () => {
    const allTime = {}
    for (const data of [snap2025, snap2026]) {
      for (const { name, totalRuns } of Object.values(data.memberTotals)) {
        allTime[name] = (allTime[name] ?? 0) + totalRuns
      }
    }
    expect(milestoneShortlist(totals(allTime)).map((c) => c.name)).toEqual(['Col', 'Claire', 'Adam'])
  })
})
