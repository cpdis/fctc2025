#!/usr/bin/env node

import { appendFile, readFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { YEARS } from '../src/config/years.js'
import { combineYearData, parseRunData } from '../src/utils/dataParser.js'
import {
  findUpcomingMilestones,
  formatMilestoneDigest,
  getAttendanceCutoff,
  getPerthCalendarDate,
  getPerthTargetWeek,
} from '../src/utils/milestones.js'
import { ResendBatchError, sendResendBatch } from './lib/resendBatch.js'

const SCRIPT_PATH = fileURLToPath(import.meta.url)
const DEFAULT_ROOT = resolve(dirname(SCRIPT_PATH), '..')
const EMAIL_PATTERN = /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/i
const SAFE_CONFIGURATION_PATTERN = /^[^\r\n\0]+$/
const SMOKE_SUBJECT = '[TEST] FCTC milestone email'
const SMOKE_TEXT = [
  'This is the fixed FCTC milestone notification smoke test.',
  '',
  'No attendance data is included.',
].join('\n')

export class MilestoneDigestError extends Error {
  constructor(category, message) {
    super(message)
    this.name = 'MilestoneDigestError'
    this.category = category
  }
}

export function parseMode(args) {
  if (!Array.isArray(args) || args.length === 0) return 'preview'
  if (args.length !== 1) {
    throw new MilestoneDigestError('mode', 'Notification mode is invalid')
  }

  const modes = { '--preview': 'preview', '--send': 'send', '--smoke': 'smoke' }
  const mode = modes[args[0]]
  if (!mode) throw new MilestoneDigestError('mode', 'Notification mode is invalid')
  return mode
}

/**
 * Load every configured season. Strict path validation prevents a changed
 * configuration from making this script read outside public/data.
 */
export async function loadAllTimeData({
  years = YEARS,
  rootDir = DEFAULT_ROOT,
  readFileImpl = readFile,
} = {}) {
  const entries = Object.entries(years ?? {})
  if (entries.length === 0) configurationError()

  const seenPaths = new Set()
  const registered = entries.map(([yearText, registeredPath]) => {
    if (!/^\d{4}$/.test(yearText)) configurationError()
    const year = Number(yearText)
    const expectedPath = `/data/${year}.csv`
    if (registeredPath !== expectedPath || seenPaths.has(registeredPath)) configurationError()
    seenPaths.add(registeredPath)
    return { year, filePath: join(rootDir, 'public', 'data', `${year}.csv`) }
  }).sort((left, right) => right.year - left.year)

  const datasets = await Promise.all(registered.map(async ({ year, filePath }) => {
    let csvText
    try {
      csvText = await readFileImpl(filePath, 'utf8')
    } catch {
      throw new MilestoneDigestError('season_unavailable', 'Registered season data is unavailable')
    }

    try {
      return parseRunData(csvText, year)
    } catch {
      throw new MilestoneDigestError('season_invalid', 'Registered season data is invalid')
    }
  }))

  return combineYearData(datasets)
}

export function parseRecipients(value) {
  if (typeof value !== 'string' || value.length === 0 || !SAFE_CONFIGURATION_PATTERN.test(value)) {
    recipientError()
  }

  const parts = value.split(',')
  if (parts.some((part) => part.trim() === '')) recipientError()

  const recipients = new Map()
  for (const part of parts) {
    const recipient = part.trim()
    if (/\s/.test(recipient) || Buffer.byteLength(recipient, 'utf8') > 254 ||
        !EMAIL_PATTERN.test(recipient)) {
      recipientError()
    }
    recipients.set(recipient.toLowerCase(), recipient.toLowerCase())
  }

  const sorted = [...recipients.values()].sort((left, right) => left.localeCompare(right, 'en'))
  if (sorted.length === 0) recipientError()
  if (sorted.length > 100) {
    throw new MilestoneDigestError(
      'recipient_limit',
      'Recipient configuration exceeds 100 addresses'
    )
  }
  return sorted
}

export function buildBatchItems({ recipients, from, subject, text }) {
  return recipients.map((recipient) => ({
    from,
    to: [recipient],
    subject,
    text,
  }))
}

/**
 * Run one preview, normal delivery, or fixed smoke delivery. Dependencies are
 * injectable so tests can prove secret short-circuiting and provider privacy.
 */
export async function runMilestoneDigest({
  args = process.argv.slice(2),
  env = process.env,
  now = new Date(),
  rootDir = DEFAULT_ROOT,
  years = YEARS,
  readFileImpl = readFile,
  appendFileImpl = appendFile,
  sendBatchImpl = sendResendBatch,
  log = console.log,
} = {}) {
  const mode = parseMode(args)
  const week = getPerthTargetWeek(now)

  if (mode === 'smoke') {
    let result
    try {
      result = await runSmoke({ env, now, week, sendBatchImpl })
    } catch (error) {
      await writeGitHubSummary({
        path: env.GITHUB_STEP_SUMMARY,
        appendFileImpl,
        mode,
        weekStart: week.weekStart,
        candidateCount: 0,
        recipientCount: 1,
        acceptedCount: 0,
        state: `failed-${safeErrorCategory(error)}`,
      })
      throw error
    }
    await writeGitHubSummary({
      path: env.GITHUB_STEP_SUMMARY,
      appendFileImpl,
      mode,
      weekStart: week.weekStart,
      candidateCount: 0,
      recipientCount: 1,
      acceptedCount: result.acceptedCount,
      state: 'accepted',
    })
    log(safeStatus({ mode, weekStart: week.weekStart, candidateCount: 0, ...result }))
    return { mode, weekStart: week.weekStart, candidateCount: 0, recipientCount: 1, ...result }
  }

  const data = await loadAllTimeData({ years, rootDir, readFileImpl })
  const candidates = findUpcomingMilestones(data.memberTotals)
  const candidateCount = candidates.length
  const digest = formatMilestoneDigest({
    candidates,
    weekStart: week.weekStart,
    cutoffDate: getAttendanceCutoff(data.runs),
  })

  await writeGitHubOutput({
    path: env.GITHUB_OUTPUT,
    appendFileImpl,
    hasCandidates: candidateCount > 0,
  })

  if (candidateCount === 0 || mode === 'preview') {
    const state = candidateCount === 0 ? 'no-candidates' : 'preview'
    const result = {
      mode,
      weekStart: week.weekStart,
      candidateCount,
      recipientCount: 0,
      acceptedCount: 0,
    }
    await writeGitHubSummary({
      path: env.GITHUB_STEP_SUMMARY,
      appendFileImpl,
      ...result,
      state,
    })
    log(safeStatus(result))
    return result
  }

  const apiKey = validateApiKey(env.RESEND_API_KEY)
  const recipients = parseRecipients(env.MILESTONE_RECIPIENTS)
  const from = validateSender(env.MILESTONE_FROM)
  const items = buildBatchItems({
    recipients,
    from,
    subject: digest.subject,
    text: digest.body,
  })

  let providerResult
  try {
    providerResult = await sendBatchImpl({
      apiKey,
      items,
      idempotencyKey: `fctc-milestones/${week.weekStart}`,
    })
  } catch (error) {
    await writeGitHubSummary({
      path: env.GITHUB_STEP_SUMMARY,
      appendFileImpl,
      mode,
      weekStart: week.weekStart,
      candidateCount,
      recipientCount: recipients.length,
      acceptedCount: 0,
      state: `failed-${safeErrorCategory(error)}`,
    })
    throw error
  }

  const result = {
    mode,
    weekStart: week.weekStart,
    candidateCount,
    recipientCount: recipients.length,
    acceptedCount: providerResult.acceptedCount,
  }
  await writeGitHubSummary({
    path: env.GITHUB_STEP_SUMMARY,
    appendFileImpl,
    ...result,
    state: 'accepted',
  })
  log(safeStatus(result))
  return result
}

async function runSmoke({ env, now, week, sendBatchImpl }) {
  const apiKey = validateApiKey(env.RESEND_API_KEY)
  const recipients = parseRecipients(env.MILESTONE_SMOKE_RECIPIENT)
  if (recipients.length !== 1) {
    throw new MilestoneDigestError('smoke_recipient', 'Smoke recipient configuration is invalid')
  }
  const from = validateSender(env.MILESTONE_FROM)
  const items = buildBatchItems({
    recipients,
    from,
    subject: SMOKE_SUBJECT,
    text: SMOKE_TEXT,
  })
  const providerResult = await sendBatchImpl({
    apiKey,
    items,
    idempotencyKey: `fctc-milestones-smoke/${getPerthCalendarDate(now)}`,
  })
  return { recipientCount: 1, acceptedCount: providerResult.acceptedCount, weekStart: week.weekStart }
}

function validateApiKey(value) {
  if (typeof value !== 'string' || value.length === 0 || !SAFE_CONFIGURATION_PATTERN.test(value)) {
    throw new MilestoneDigestError('api_key', 'Provider credential is invalid')
  }
  return value
}

function validateSender(value) {
  if (typeof value !== 'string' || value.trim() !== value ||
      !SAFE_CONFIGURATION_PATTERN.test(value)) {
    throw new MilestoneDigestError('sender', 'Sender configuration is invalid')
  }

  const friendlyMatch = /^[^<>]+ <([^<>\s]+)>$/.exec(value)
  const bareMatch = /^([^<>\s]+)$/.exec(value)
  const address = friendlyMatch?.[1] ?? bareMatch?.[1]
  if (!address || !EMAIL_PATTERN.test(address)) {
    throw new MilestoneDigestError('sender', 'Sender configuration is invalid')
  }
  return value
}

async function writeGitHubOutput({ path, appendFileImpl, hasCandidates }) {
  if (!path) return
  await appendFileImpl(path, `has_candidates=${hasCandidates}\n`, 'utf8')
}

async function writeGitHubSummary({
  path,
  appendFileImpl,
  mode,
  weekStart,
  candidateCount,
  recipientCount,
  acceptedCount,
  state,
}) {
  if (!path) return
  const summary = [
    '### FCTC milestone notification',
    '',
    '| Field | Value |',
    '| --- | --- |',
    `| Mode | ${mode} |`,
    `| Target week | ${weekStart} |`,
    `| Candidate count | ${candidateCount} |`,
    `| Recipient count | ${recipientCount} |`,
    `| Accepted item count | ${acceptedCount} |`,
    `| State | ${state} |`,
    '',
  ].join('\n')
  await appendFileImpl(path, summary, 'utf8')
}

function safeStatus({ mode, weekStart, candidateCount, acceptedCount }) {
  return `milestone_notification mode=${mode} week=${weekStart} candidates=${candidateCount} accepted=${acceptedCount}`
}

export function safeErrorCategory(error) {
  if (error instanceof ResendBatchError || error instanceof MilestoneDigestError) {
    return error.category
  }
  return 'unexpected'
}

function configurationError() {
  throw new MilestoneDigestError(
    'season_configuration',
    'Registered season configuration is invalid'
  )
}

function recipientError() {
  throw new MilestoneDigestError('recipient', 'Recipient configuration is invalid')
}

async function main() {
  try {
    await runMilestoneDigest()
  } catch (error) {
    const status = Number.isInteger(error?.status) ? ` status=${error.status}` : ''
    console.error(`milestone_notification failed category=${safeErrorCategory(error)}${status}`)
    process.exitCode = 1
  }
}

if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
  await main()
}
