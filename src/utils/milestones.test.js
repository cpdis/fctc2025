import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { combineYearData, parseRunData } from './dataParser'
import {
  findUpcomingMilestones,
  formatMilestoneDigest,
  getAttendanceCutoff,
  getPerthCalendarDate,
  getPerthTargetWeek,
} from './milestones'

const fixtureDir = join(import.meta.dirname, '..', 'test', 'fixtures')

function totals(entries) {
  return Object.fromEntries(
    entries.map(([name, totalRuns]) => [name, { name, totalRuns, totalKm: 0 }])
  )
}

function catchError(callback) {
  try {
    callback()
  } catch (error) {
    return error
  }
  throw new Error('Expected callback to throw')
}

describe('findUpcomingMilestones', () => {
  it('selects every positive 50n - 1 boundary without a fixed maximum', () => {
    const candidates = findUpcomingMilestones(totals([
      ['Zero', 0],
      ['Forty Eight', 48],
      ['Forty Nine', 49],
      ['Fifty', 50],
      ['Ninety Eight', 98],
      ['Ninety Nine', 99],
      ['One Forty Nine', 149],
      ['One Ninety Nine', 199],
      ['Two Forty Nine', 249],
      ['No Ceiling', 999],
    ]))

    expect(candidates).toEqual([
      { name: 'Forty Nine', currentRuns: 49, milestone: 50 },
      { name: 'Ninety Nine', currentRuns: 99, milestone: 100 },
      { name: 'One Forty Nine', currentRuns: 149, milestone: 150 },
      { name: 'One Ninety Nine', currentRuns: 199, milestone: 200 },
      { name: 'Two Forty Nine', currentRuns: 249, milestone: 250 },
      { name: 'No Ceiling', currentRuns: 999, milestone: 1000 },
    ])
  })

  it('sorts by milestone and then normalized name using a fixed locale', () => {
    const candidates = findUpcomingMilestones(totals([
      ['Zoë', 49],
      ['Later', 99],
      ['Ámy', 49],
      ['Sam (Coach) 🏃', 49],
    ]))

    expect(candidates.map(({ name, milestone }) => [name, milestone])).toEqual([
      ['Ámy', 50],
      ['Sam (Coach) 🏃', 50],
      ['Zoë', 50],
      ['Later', 100],
    ])
  })

  it('preserves exact punctuation and emoji in candidate names', () => {
    const name = 'Alex 👑, Jr. (Coach)'

    expect(findUpcomingMilestones(totals([[name, 49]]))).toEqual([
      { name, currentRuns: 49, milestone: 50 },
    ])
  })

  it.each([
    ['C0 control', 'Alice\u0000Admin'],
    ['newline control', 'Alice\nAdmin'],
    ['Unicode line separator', 'Alice\u2028Admin'],
    ['Unicode paragraph separator', 'Alice\u2029Admin'],
    ['bidirectional override', 'Alice\u202eAdmin'],
    ['bidirectional isolate', 'Alice\u2066Admin'],
  ])('rejects a %s without echoing the name', (_label, name) => {
    const error = catchError(() => findUpcomingMilestones(totals([[name, 49]])))

    expect(error.message).toBe('Candidate name is unsafe')
    expect(error.message).not.toContain(name)
  })

  it('accepts 200 Unicode code points and rejects 201 without echoing the name', () => {
    const acceptedName = 'a'.repeat(200)
    const rejectedName = 'b'.repeat(201)

    expect(findUpcomingMilestones(totals([[acceptedName, 49]]))[0].name).toBe(acceptedName)

    const error = catchError(() => findUpcomingMilestones(totals([[rejectedName, 49]])))
    expect(error.message).toBe('Candidate name is too long')
    expect(error.message).not.toContain(rejectedName)
  })

  it('uses exact totals from the real parser and all-time merge', () => {
    const data2025 = parseRunData(readFileSync(join(fixtureDir, '2025.csv'), 'utf8'), 2025)
    const data2026 = parseRunData(readFileSync(join(fixtureDir, '2026.csv'), 'utf8'), 2026)
    const allTime = combineYearData([data2025, data2026])

    expect(allTime.memberTotals.Darren.totalRuns).toBe(49)
    expect(findUpcomingMilestones(allTime.memberTotals)).toEqual([
      { name: 'Darren', currentRuns: 49, milestone: 50 },
    ])
    expect(getAttendanceCutoff(allTime.runs)).toBe('2026-05-25')
  })
})

describe('getPerthTargetWeek', () => {
  it('returns the Perth calendar date for a supplied instant', () => {
    expect(getPerthCalendarDate(new Date('2026-08-16T16:05:00.000Z'))).toBe('2026-08-17')
  })

  it('targets the next Monday when the Perth date is Sunday', () => {
    expect(getPerthTargetWeek(new Date('2026-08-16T08:00:00.000Z'))).toEqual({
      weekStart: '2026-08-17',
      weekEnd: '2026-08-23',
    })
  })

  it('targets the current Monday for a delayed job after Perth midnight', () => {
    expect(getPerthTargetWeek(new Date('2026-08-16T16:05:00.000Z'))).toEqual({
      weekStart: '2026-08-17',
      weekEnd: '2026-08-23',
    })
  })

  it('handles a target week that crosses a month boundary', () => {
    expect(getPerthTargetWeek(new Date('2026-08-30T04:00:00.000Z'))).toEqual({
      weekStart: '2026-08-31',
      weekEnd: '2026-09-06',
    })
  })

  it('handles a target week that crosses a year boundary', () => {
    expect(getPerthTargetWeek(new Date('2023-12-31T04:00:00.000Z'))).toEqual({
      weekStart: '2024-01-01',
      weekEnd: '2024-01-07',
    })
  })

  it('rejects an invalid injected clock value', () => {
    expect(() => getPerthTargetWeek(new Date('invalid'))).toThrow('Clock must be a valid Date')
  })
})

describe('getAttendanceCutoff', () => {
  it('uses the newest valid parsed run with recorded attendance', () => {
    const runs = [
      { parsedDate: new Date(2026, 7, 9), totalAttendance: 12 },
      { parsedDate: new Date(2026, 7, 16), totalAttendance: 0 },
      { parsedDate: new Date('invalid'), totalAttendance: 20 },
      { parsedDate: new Date(2026, 7, 14), totalAttendance: 1 },
    ]

    expect(getAttendanceCutoff(runs)).toBe('2026-08-14')
  })

  it('returns null when no run has a valid date and positive attendance', () => {
    expect(getAttendanceCutoff([
      { parsedDate: new Date(2026, 7, 16), totalAttendance: 0 },
      { parsedDate: null, totalAttendance: 4 },
    ])).toBeNull()
  })
})

describe('formatMilestoneDigest', () => {
  const weekStart = '2026-08-17'
  const cutoffDate = '2026-08-16'

  it('returns no content when there are no candidates', () => {
    expect(formatMilestoneDigest({ candidates: [], weekStart, cutoffDate })).toBeNull()
  })

  it('formats one deterministic text and HTML digest with plural grammar', () => {
    const candidates = findUpcomingMilestones(totals([
      ['Sam Lee', 149],
      ['Jane Doe', 99],
    ]))

    const digest = formatMilestoneDigest({ candidates, weekStart, cutoffDate })

    expect(digest).toMatchObject({
      subject: 'FCTC milestone runs — week of 17 Aug 2026',
      body: [
        '2 runners are one recorded run from a milestone:',
        '',
        '- Jane Doe — 100th run',
        '- Sam Lee — 150th run',
        '',
        'Based on FCTC attendance recorded through 16 Aug 2026.',
      ].join('\n'),
    })
    expect(digest.html).toContain('<meta name="viewport" content="width=device-width, initial-scale=1">')
    expect(digest.html).toContain('background: #ffffff')
    expect(digest.html).toContain('#ffd23f')
    expect(digest.html).toContain('#ff7a30')
    expect(digest.html).toContain('#e8442c')
    expect(digest.html).toContain('WEEK OF 17 AUGUST 2026')
    expect(digest.html).toContain('MILESTONES<br>AHEAD')
    expect(digest.html).toContain('Jane Doe')
    expect(digest.html).toContain('Approaching their 100th run')
    expect(digest.html).toContain('Sam Lee')
    expect(digest.html).toContain('Approaching their 150th run')
    expect(digest.html).toContain('Attendance recorded through 16 Aug 2026.')
    expect(digest.html).toContain('href="https://fctc.fun/dashboard"')
    expect(digest.html).not.toContain('<img')
  })

  it('escapes candidate names before adding them to HTML', () => {
    const name = 'Alex & <Runner> "Quoted"'
    const [candidate] = findUpcomingMilestones(totals([[name, 49]]))

    const digest = formatMilestoneDigest({ candidates: [candidate], weekStart, cutoffDate })

    expect(digest.body).toContain(name)
    expect(digest.html).toContain('Alex &amp; &lt;Runner&gt; &quot;Quoted&quot;')
    expect(digest.html).not.toContain(name)
  })

  it('uses singular grammar for one candidate', () => {
    const [candidate] = findUpcomingMilestones(totals([['Jane Doe', 49]]))

    const digest = formatMilestoneDigest({ candidates: [candidate], weekStart, cutoffDate })

    expect(digest.body).toContain('1 runner is one recorded run from a milestone:')
    expect(digest.html).toContain('One scoundrel could reach a landmark run this week.')
    expect(digest.html).toContain('One FCTC runner is approaching a milestone run this week.')
    expect(digest.html).not.toContain('scoundrels could reach')
  })

  it('produces byte-stable content regardless of member insertion order', () => {
    const first = findUpcomingMilestones(totals([['Zoë', 49], ['Amy', 49]]))
    const second = findUpcomingMilestones(totals([['Amy', 49], ['Zoë', 49]]))

    const firstDigest = formatMilestoneDigest({ candidates: first, weekStart, cutoffDate })
    const secondDigest = formatMilestoneDigest({ candidates: second, weekStart, cutoffDate })

    expect(new TextEncoder().encode(firstDigest.body)).toEqual(
      new TextEncoder().encode(secondDigest.body)
    )
    expect(firstDigest).toEqual(secondDigest)
  })

  it('fails closed when candidates exist without a valid attendance cutoff', () => {
    const candidates = findUpcomingMilestones(totals([['Jane Doe', 49]]))

    expect(() => formatMilestoneDigest({ candidates, weekStart, cutoffDate: null }))
      .toThrow('Attendance cutoff is unavailable')
  })

  it('rejects an unsafe name supplied directly to the formatter without echoing it', () => {
    const name = 'Alice\u202eAdmin'
    const error = catchError(() => formatMilestoneDigest({
      candidates: [{ name, currentRuns: 49, milestone: 50 }],
      weekStart,
      cutoffDate,
    }))

    expect(error.message).toBe('Candidate name is unsafe')
    expect(error.message).not.toContain(name)
  })

  it('rejects a body over 64 KiB without echoing its content', () => {
    const entries = Array.from({ length: 350 }, (_, index) => [
      `Runner ${String(index).padStart(4, '0')} ${'x'.repeat(188)}`,
      49,
    ])
    const candidates = findUpcomingMilestones(totals(entries))
    const error = catchError(() => {
      formatMilestoneDigest({ candidates, weekStart, cutoffDate })
    })

    expect(error.message).toBe('Milestone digest exceeds 64 KiB')
    expect(error.message).not.toContain('Runner')
  })

  it('rejects HTML over 256 KiB while the text body remains within its limit', () => {
    const candidates = Array.from({ length: 300 }, (_, index) => ({
      name: `Runner ${String(index).padStart(4, '0')}`,
      currentRuns: 49,
      milestone: 50,
    }))

    expect(() => formatMilestoneDigest({ candidates, weekStart, cutoffDate }))
      .toThrow('Milestone HTML exceeds 256 KiB')
  })

  it('can include the same unchanged candidate in the following target week', () => {
    const firstWeek = getPerthTargetWeek(new Date('2026-08-16T04:00:00.000Z'))
    const nextWeek = getPerthTargetWeek(new Date('2026-08-23T04:00:00.000Z'))
    const candidates = findUpcomingMilestones(totals([['Jane Doe', 49]]))

    const first = formatMilestoneDigest({
      candidates,
      weekStart: firstWeek.weekStart,
      cutoffDate,
    })
    const next = formatMilestoneDigest({
      candidates,
      weekStart: nextWeek.weekStart,
      cutoffDate,
    })

    expect(first.body).toContain('- Jane Doe — 50th run')
    expect(next.body).toContain('- Jane Doe — 50th run')
    expect(next.subject).toBe('FCTC milestone runs — week of 24 Aug 2026')
  })
})
