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
  const rows = Array.from({ length: count }, (_, index) => {
    const day = (index % 28) + 1
    return `"Fri, ${day}-Jan",Meet,Social,5,5,x,0`
  })
  return [
    'Summary row',
    `Date,Meet,Run,Approx kms,Actual kms,${name},+1's`,
    ...rows,
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

  it('sends one private item per validated recipient with the weekly key', async () => {
    const options = runOptions({
      args: ['--send'],
      env: {
        RESEND_API_KEY: 're_private',
        MILESTONE_RECIPIENTS: 'two@example.com,one@example.com',
        MILESTONE_FROM: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
      },
      sendBatchImpl: vi.fn().mockResolvedValue({ acceptedCount: 2 }),
    })

    await expect(runMilestoneDigest(options)).resolves.toMatchObject({
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
    expect(request.items[0].text).toBe(request.items[1].text)
    expect(request.items[0].html).toContain('Jane Doe')
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
    expect(request.items[0].html).toContain('Approaching their 50th run')
    expect(request.items[0].html).not.toContain('Jane Doe')
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
