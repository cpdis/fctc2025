// @vitest-environment node

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it, vi } from 'vitest'
import {
  buildBatchItems,
  loadAllTimeData,
  parseMode,
  parseRecipients,
  runMilestoneDigest,
} from './send-milestone-digest.js'
import { ResendBatchError } from './lib/resendBatch.js'
import { findUpcomingMilestones, getAttendanceCutoff } from '../src/utils/milestones.js'

const fixtureDir = join(import.meta.dirname, '..', 'src', 'test', 'fixtures')
const csv2025 = readFileSync(join(fixtureDir, '2025.csv'), 'utf8')
const csv2026 = readFileSync(join(fixtureDir, '2026.csv'), 'utf8')
const REGISTERED_YEARS = { 2025: '/data/2025.csv', 2026: '/data/2026.csv' }

function fixtureReader(paths = {}) {
  const values = {
    '/repo/public/data/2025.csv': csv2025,
    '/repo/public/data/2026.csv': csv2026,
    ...paths,
  }
  return vi.fn(async (path) => {
    if (!(path in values)) throw new Error('missing')
    const value = values[path]
    if (value instanceof Error) throw value
    return value
  })
}

function attendanceCsv(name, count, year = 2026) {
  return attendanceCsvForMembers([[name, count]], year)
}

function attendanceCsvForMembers(entries, year = 2026) {
  const rows = Array.from({ length: Math.max(...entries.map(([, count]) => count)) }, (_, index) => {
    const day = (index % 28) + 1
    const attendance = entries.map(([, count]) => index < count ? 'x' : '').join(',')
    return `"Fri, ${day}-Jan",Meet,Social,5,5,${attendance},0`
  })
  return [
    'Summary row',
    `Date,Meet,Run,Approx kms,Actual kms,${entries.map(([name]) => name).join(',')},+1's`,
    ...rows,
    `,,${year}`,
  ].join('\n')
}

function forecastChanceCsv(name, year = 2026) {
  const weekdays = ['Mon', 'Wed', 'Fri']
  const attendedRows = Array.from({ length: 49 }, (_, index) => {
    const month = index < 28 ? 'Jan' : 'Feb'
    const day = index < 28 ? index + 1 : index - 27
    return `"${weekdays[index % weekdays.length]}, ${day}-${month}",Meet,Social,5,5,x,,0`
  })
  const absenceRows = weekdays.map((weekday, index) => (
    `"${weekday}, ${index + 22}-Feb",Meet,Social,5,5,,x,0`
  ))

  return [
    'Summary row',
    `Date,Meet,Run,Approx kms,Actual kms,${name},Other Runner,+1's`,
    ...attendedRows,
    ...absenceRows,
    `,,${year}`,
  ].join('\n')
}

function manualRetryCsv(name, year = 2026) {
  const priorRuns = [
    ['Mon', 5],
    ['Wed', 7],
    ['Fri', 9],
  ].map(([weekday, day]) => `"${weekday}, ${day}-Jan",Meet,Social,5,5,x,0`)
  const fillerRuns = Array.from(
    { length: 43 },
    () => '"Sat, 3-Jan",Meet,Social,5,5,x,0'
  )

  return [
    'Summary row',
    `Date,Meet,Run,Approx kms,Actual kms,${name},+1's`,
    ...fillerRuns,
    ...priorRuns,
    '"Mon, 17-Aug",Meet,Social,5,5,x,0',
    '"Wed, 19-Aug",Meet,Social,5,5,x,0',
    `,,${year}`,
  ].join('\n')
}

function thresholdForecastCsv(year = 2026) {
  const fillerRuns = Array.from(
    { length: 45 },
    () => '"Sat, 3-Jan",Meet,Social,5,5,x,x,x,0'
  )
  const opportunityRows = [
    '"Mon, 5-Jan",Meet,Social,5,5,,x,x,0',
    '"Wed, 7-Jan",Meet,Social,5,5,,x,x,0',
    '"Fri, 9-Jan",Meet,Social,5,5,,x,x,0',
    '"Mon, 12-Jan",Meet,Social,5,5,x,,x,0',
    '"Wed, 14-Jan",Meet,Social,5,5,x,,x,0',
    '"Fri, 16-Jan",Meet,Social,5,5,x,,x,0',
  ]

  return [
    'Summary row',
    "Date,Meet,Run,Approx kms,Actual kms,Above Gate,Below Gate,History Anchor,+1's",
    ...fillerRuns,
    ...opportunityRows,
    `,,${year}`,
  ].join('\n')
}

function runOptions(overrides = {}) {
  return {
    args: ['--preview'],
    env: {},
    now: new Date('2026-08-16T09:17:00.000Z'),
    rootDir: '/repo',
    years: { 2026: '/data/2026.csv' },
    readFileImpl: fixtureReader({
      '/repo/public/data/2026.csv': attendanceCsv('Jane Doe', 49),
    }),
    appendFileImpl: vi.fn().mockResolvedValue(undefined),
    sendBatchImpl: vi.fn().mockResolvedValue({ acceptedCount: 1 }),
    log: vi.fn(),
    ...overrides,
  }
}

describe('parseMode', () => {
  it('defaults to preview and accepts each explicit mode', () => {
    expect(parseMode([])).toBe('preview')
    expect(parseMode(['--preview'])).toBe('preview')
    expect(parseMode(['--send'])).toBe('send')
    expect(parseMode(['--smoke'])).toBe('smoke')
  })

  it.each([
    ['--unknown'],
    ['--preview', '--send'],
    ['--send', 'extra'],
  ])('rejects unknown or conflicting arguments', (...args) => {
    expect(() => parseMode(args)).toThrow('Notification mode is invalid')
  })
})

describe('loadAllTimeData', () => {
  it('loads and merges every registered season with the real parser', async () => {
    const data = await loadAllTimeData({
      years: REGISTERED_YEARS,
      rootDir: '/repo',
      readFileImpl: fixtureReader(),
    })

    expect(data.runs.length).toBeGreaterThan(100)
    expect(data.memberTotals.Darren.totalRuns).toBe(49)
  })

  it.each([
    ['malformed path', { 2025: 'data/2025.csv' }],
    ['year mismatch', { 2025: '/data/2026.csv' }],
    ['duplicate path', { 2025: '/data/2025.csv', 2026: '/data/2025.csv' }],
    ['non-year key', { latest: '/data/latest.csv' }],
  ])('fails closed for a %s', async (_label, years) => {
    await expect(loadAllTimeData({
      years,
      rootDir: '/repo',
      readFileImpl: fixtureReader(),
    })).rejects.toThrow('Registered season configuration is invalid')
  })

  it('fails closed when a registered season is missing', async () => {
    await expect(loadAllTimeData({
      years: REGISTERED_YEARS,
      rootDir: '/repo',
      readFileImpl: fixtureReader({ '/repo/public/data/2026.csv': new Error('private path') }),
    })).rejects.toThrow('Registered season data is unavailable')
  })

  it('fails closed when a registered season cannot parse', async () => {
    await expect(loadAllTimeData({
      years: REGISTERED_YEARS,
      rootDir: '/repo',
      readFileImpl: fixtureReader({ '/repo/public/data/2026.csv': 'not a valid sheet' }),
    })).rejects.toThrow('Registered season data is invalid')
  })
})

describe('parseRecipients', () => {
  it('trims, lowercases, deduplicates case-insensitively, and sorts addresses', () => {
    expect(parseRecipients(' ZED@example.com,amy@example.com,zed@EXAMPLE.com ')).toEqual([
      'amy@example.com',
      'zed@example.com',
    ])
  })

  it.each([
    ['', 'empty list'],
    ['first@example.com,', 'empty item'],
    ['First Person <first@example.com>', 'display name'],
    ['first @example.com', 'whitespace'],
    ['first\n@example.com', 'newline'],
    ['first\0@example.com', 'NUL'],
    ['not-an-email', 'invalid mailbox'],
    ['.first@example.com', 'leading local-part dot'],
    ['first.@example.com', 'trailing local-part dot'],
    ['first..last@example.com', 'consecutive local-part dots'],
    [`${'a'.repeat(65)}@example.com`, 'oversized local part'],
    [`${'a'.repeat(245)}@example.com`, 'oversized mailbox'],
  ])('rejects an invalid recipient: %s', (value) => {
    let error
    try {
      parseRecipients(value)
    } catch (caught) {
      error = caught
    }

    expect(error.message).toBe('Recipient configuration is invalid')
    if (value) expect(error.message).not.toContain(value)
  })

  it('rejects more than 100 recipients', () => {
    const value = Array.from({ length: 101 }, (_, index) => `person${index}@example.com`).join(',')
    expect(() => parseRecipients(value)).toThrow('Recipient configuration exceeds 100 addresses')
  })
})

describe('buildBatchItems', () => {
  it('creates one private item per recipient with identical content', () => {
    const items = buildBatchItems({
      recipients: ['one@example.com', 'two@example.com'],
      from: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
      subject: 'Subject',
      text: 'Body',
      html: '<p>Body</p>',
    })

    expect(items).toEqual([
      {
        from: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
        to: ['one@example.com'],
        subject: 'Subject',
        text: 'Body',
        html: '<p>Body</p>',
      },
      {
        from: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
        to: ['two@example.com'],
        subject: 'Subject',
        text: 'Body',
        html: '<p>Body</p>',
      },
    ])
  })

  it('rejects a missing HTML part', () => {
    expect(() => buildBatchItems({
      recipients: ['one@example.com'],
      from: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
      subject: 'Subject',
      text: 'Body',
    })).toThrow('Email HTML is invalid')
  })
})

describe('runMilestoneDigest', () => {
  it('previews candidates without a provider request or GitHub files', async () => {
    const options = runOptions()

    await expect(runMilestoneDigest(options)).resolves.toMatchObject({
      mode: 'preview',
      weekStart: '2026-08-17',
      candidateCount: 1,
      acceptedCount: 0,
    })
    expect(options.sendBatchImpl).not.toHaveBeenCalled()
    expect(options.appendFileImpl).not.toHaveBeenCalled()
    expect(options.log).toHaveBeenCalledWith(
      'milestone_notification mode=preview week=2026-08-17 candidates=1 accepted=0'
    )
  })

  it('writes only safe counts to optional GitHub output and summary files', async () => {
    const appendFileImpl = vi.fn().mockResolvedValue(undefined)
    const options = runOptions({
      env: {
        GITHUB_OUTPUT: '/github/output',
        GITHUB_STEP_SUMMARY: '/github/summary',
      },
      appendFileImpl,
    })

    await runMilestoneDigest(options)

    const written = appendFileImpl.mock.calls.map(([, content]) => content).join('\n')
    expect(written).toContain('has_candidates=true')
    expect(written).toContain('Candidate count | 1')
    expect(written).not.toContain('Jane Doe')
    expect(written).not.toContain('@')
  })

  it('exits before reading send secrets when no candidate exists', async () => {
    const env = new Proxy({}, {
      get(target, property) {
        if (['RESEND_API_KEY', 'MILESTONE_RECIPIENTS', 'MILESTONE_FROM'].includes(property)) {
          throw new Error('send secret was read')
        }
        return target[property]
      },
    })
    const options = runOptions({
      args: ['--send'],
      env,
      readFileImpl: fixtureReader({
        '/repo/public/data/2026.csv': attendanceCsv('Jane Doe', 48),
      }),
    })

    await expect(runMilestoneDigest(options)).resolves.toMatchObject({
      candidateCount: 0,
      acceptedCount: 0,
    })
    expect(options.sendBatchImpl).not.toHaveBeenCalled()
  })

  it('does not reuse completed target runs during a Wednesday retry', async () => {
    const options = runOptions({
      args: ['--send'],
      now: new Date('2026-08-19T05:00:00.000Z'),
      readFileImpl: fixtureReader({
        '/repo/public/data/2026.csv': manualRetryCsv('Needs Two Runs'),
      }),
    })

    await expect(runMilestoneDigest(options)).resolves.toMatchObject({
      weekStart: '2026-08-17',
      candidateCount: 0,
      acceptedCount: 0,
    })
    expect(options.sendBatchImpl).not.toHaveBeenCalled()
  })

  it('connects parsed weekday history to the raw 50 percent gate', async () => {
    const data = await loadAllTimeData({
      years: { 2026: '/data/2026.csv' },
      rootDir: '/repo',
      readFileImpl: fixtureReader({
        '/repo/public/data/2026.csv': thresholdForecastCsv(),
      }),
    })
    const targetWeek = { weekStart: '2026-01-19', weekEnd: '2026-01-25' }
    const candidates = findUpcomingMilestones(
      data.memberTotals,
      data.runs,
      getAttendanceCutoff(data.runs),
      targetWeek
    )

    expect(candidates).toHaveLength(1)
    expect(candidates[0]).toMatchObject({
      name: 'Above Gate',
      currentRuns: 48,
      runsNeeded: 2,
      label: 'Likely',
    })
    expect(candidates[0].chance).toBeCloseTo(0.5324506750080484, 12)
    expect(candidates[0].chance).toBeGreaterThan(0.5)
    expect(candidates.map(({ name }) => name)).not.toContain('Below Gate')
  })

  it('sends one private item per validated recipient with the weekly key', async () => {
    const options = runOptions({
      args: ['--send'],
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_RECIPIENTS: 'two@example.com,one@example.com',
        MILESTONE_FROM: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
      },
      readFileImpl: fixtureReader({
        '/repo/public/data/2026.csv': attendanceCsvForMembers([
          ['Jane Doe', 49],
          ['Sam Lee', 49],
        ]),
      }),
      sendBatchImpl: vi.fn().mockResolvedValue({ acceptedCount: 2 }),
    })

    await expect(runMilestoneDigest(options)).resolves.toMatchObject({
      candidateCount: 2,
      recipientCount: 2,
      acceptedCount: 2,
    })

    const request = options.sendBatchImpl.mock.calls[0][0]
    expect(request.idempotencyKey).toBe('fctc-milestones/2026-08-17')
    expect(request.items.map(({ to }) => to)).toEqual([
      ['one@example.com'],
      ['two@example.com'],
    ])
    expect(request.items[0].text).toContain('Jane Doe')
    expect(request.items[0].text).toContain('Sam Lee')
    expect(request.items[0].text).toContain('Very likely · needs 1 run')
    expect(request.items[0].text).toBe(request.items[1].text)
    expect(request.items[0].html).toContain('Jane Doe')
    expect(request.items[0].html).toContain('Sam Lee')
    expect(request.items[0].html).toContain('Very likely &middot; needs 1 run')
    expect(request.items[0].html).toContain('href="https://fctc.fun/dashboard"')
    expect(request.items[0].html).toBe(request.items[1].html)
  })

  it('sends fixed smoke content without reading attendance data', async () => {
    const options = runOptions({
      args: ['--smoke'],
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_SMOKE_RECIPIENT: 'colin@example.com',
        MILESTONE_FROM: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
        GITHUB_RUN_ID: '123456789',
        GITHUB_RUN_ATTEMPT: '2',
      },
      readFileImpl: vi.fn().mockRejectedValue(new Error('attendance must not be read')),
    })

    await expect(runMilestoneDigest(options)).resolves.toMatchObject({
      mode: 'smoke',
      candidateCount: 0,
      recipientCount: 1,
      acceptedCount: 1,
    })

    expect(options.readFileImpl).not.toHaveBeenCalled()
    const request = options.sendBatchImpl.mock.calls[0][0]
    expect(request.idempotencyKey).toBe('fctc-milestones-smoke/123456789/2')
    expect(request.items[0]).toMatchObject({
      to: ['colin@example.com'],
      subject: '[TEST] FCTC milestone email',
    })
    expect(request.items[0].text).not.toContain('Jane Doe')
    expect(request.items[0].text).not.toContain('run from')
    expect(request.items[0].html).toContain('FCTC Test Runner')
    expect(request.items[0].html).toContain('Very likely &middot; needs 1 run for their 50th run')
    expect(request.items[0].html).not.toContain('Jane Doe')
  })

  it('keeps the exact forecast chance out of email, logs, and workflow summaries', async () => {
    const privateName = 'Private Forecast Runner'
    const csv = forecastChanceCsv(privateName)
    const readFileImpl = fixtureReader({ '/repo/public/data/2026.csv': csv })
    const data = await loadAllTimeData({
      years: { 2026: '/data/2026.csv' },
      rootDir: '/repo',
      readFileImpl,
    })
    const cutoffDate = getAttendanceCutoff(data.runs)
    const [candidate] = findUpcomingMilestones(data.memberTotals, data.runs, cutoffDate)
    const chanceSentinel = String(candidate.chance)
    expect(candidate.chance).toBeGreaterThan(0)
    expect(candidate.chance).toBeLessThan(1)

    const appendFileImpl = vi.fn().mockResolvedValue(undefined)
    const log = vi.fn()
    const options = runOptions({
      args: ['--send'],
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_RECIPIENTS: 'private@example.com',
        MILESTONE_FROM: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
        GITHUB_STEP_SUMMARY: '/github/summary',
      },
      readFileImpl: fixtureReader({ '/repo/public/data/2026.csv': csv }),
      appendFileImpl,
      log,
    })

    await runMilestoneDigest(options)

    const request = options.sendBatchImpl.mock.calls[0][0]
    const logs = log.mock.calls.flat().join('\n')
    const summary = appendFileImpl.mock.calls.map(([, content]) => content).join('\n')
    expect(`${request.items[0].subject}\n${request.items[0].text}\n${request.items[0].html}`)
      .not.toContain(chanceSentinel)
    expect(logs).not.toContain(chanceSentinel)
    expect(summary).not.toContain(chanceSentinel)
    expect(summary).not.toContain(privateName)
  })

  it('writes a safe failed state when the smoke provider request fails', async () => {
    const appendFileImpl = vi.fn().mockResolvedValue(undefined)
    const options = runOptions({
      args: ['--smoke'],
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_SMOKE_RECIPIENT: 'colin@example.com',
        MILESTONE_FROM: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
        GITHUB_STEP_SUMMARY: '/github/summary',
      },
      appendFileImpl,
      sendBatchImpl: vi.fn().mockRejectedValue(
        new ResendBatchError('authentication', { status: 401 })
      ),
    })

    await expect(runMilestoneDigest(options)).rejects.toMatchObject({
      category: 'authentication',
    })

    const written = appendFileImpl.mock.calls.map(([, content]) => content).join('\n')
    expect(written).toContain('failed-authentication')
    expect(written).not.toContain('re_private')
    expect(written).not.toContain('colin@example.com')
  })

  it('writes a safe failed state when a normal provider request fails', async () => {
    const appendFileImpl = vi.fn().mockResolvedValue(undefined)
    const options = runOptions({
      args: ['--send'],
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_RECIPIENTS: 'private@example.com',
        MILESTONE_FROM: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
        GITHUB_STEP_SUMMARY: '/github/summary',
      },
      appendFileImpl,
      sendBatchImpl: vi.fn().mockRejectedValue(
        new ResendBatchError('provider_temporary', { status: 503, attempts: 3 })
      ),
    })

    await expect(runMilestoneDigest(options)).rejects.toMatchObject({
      category: 'provider_temporary',
    })

    const written = appendFileImpl.mock.calls.map(([, content]) => content).join('\n')
    expect(written).toContain('Candidate count | 1')
    expect(written).toContain('Recipient count | 1')
    expect(written).toContain('Accepted item count | 0')
    expect(written).toContain('failed-provider_temporary')
    expect(written).not.toContain('Jane Doe')
    expect(written).not.toContain('private@example.com')
    expect(written).not.toContain('re_private')
  })

  it('rejects malformed sender syntax before a provider request', async () => {
    const options = runOptions({
      args: ['--send'],
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_RECIPIENTS: 'private@example.com',
        MILESTONE_FROM: 'runs@notifications.fctc.cpd.dev>',
      },
    })

    await expect(runMilestoneDigest(options)).rejects.toThrow('Sender configuration is invalid')
    expect(options.sendBatchImpl).not.toHaveBeenCalled()
  })

  it('rejects invalid dot-atom sender syntax before a provider request', async () => {
    const options = runOptions({
      args: ['--send'],
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_RECIPIENTS: 'private@example.com',
        MILESTONE_FROM: 'FCTC Milestones <runs..team@notifications.fctc.cpd.dev>',
      },
    })

    await expect(runMilestoneDigest(options)).rejects.toThrow('Sender configuration is invalid')
    expect(options.sendBatchImpl).not.toHaveBeenCalled()
  })

  it('keeps private data out of status logging', async () => {
    const log = vi.fn()
    const options = runOptions({
      args: ['--send'],
      log,
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_RECIPIENTS: 'private@example.com',
        MILESTONE_FROM: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
      },
    })

    await runMilestoneDigest(options)

    const output = log.mock.calls.flat().join('\n')
    expect(output).toContain('candidates=1')
    expect(output).toContain('accepted=1')
    expect(output).not.toContain('Jane Doe')
    expect(output).not.toContain('private@example.com')
    expect(output).not.toContain('re_private')
  })
})
