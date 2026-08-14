const PERTH_TIME_ZONE = 'Australia/Perth'
const MAX_NAME_CODE_POINTS = 200
const MAX_BODY_BYTES = 64 * 1024

// Keep the sort independent from the machine locale. The code-point tie-breakers
// also make canonically equivalent or case-equivalent names deterministic.
const NAME_COLLATOR = new Intl.Collator('en-AU', {
  usage: 'sort',
  sensitivity: 'base',
  numeric: true,
})

const PERTH_DATE_FORMATTER = new Intl.DateTimeFormat('en-AU', {
  timeZone: PERTH_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  weekday: 'short',
})

const DISPLAY_DATE_FORMATTER = new Intl.DateTimeFormat('en-AU', {
  timeZone: 'UTC',
  day: 'numeric',
  month: 'short',
  year: 'numeric',
})

// C0/C1 controls, explicit line separators, and bidirectional embedding,
// override, and isolate controls can change or conceal plain-text email content.
const UNSAFE_NAME_PATTERN = /[\p{Cc}\u2028\u2029\u202a-\u202e\u2066-\u2069]/u

/**
 * Find members whose next recorded run is a positive multiple of 50.
 *
 * @param {Record<string, { name: string, totalRuns: number }>} memberTotals
 * @returns {Array<{ name: string, currentRuns: number, milestone: number }>}
 */
export function findUpcomingMilestones(memberTotals) {
  const candidates = []

  for (const member of Object.values(memberTotals ?? {})) {
    const currentRuns = member?.totalRuns
    const milestone = currentRuns + 1

    if (!Number.isInteger(currentRuns) || milestone <= 0 || milestone % 50 !== 0) continue

    assertSafeCandidateName(member.name)
    candidates.push({ name: member.name, currentRuns, milestone })
  }

  return candidates.sort(compareCandidates)
}

/**
 * Calculate the Monday-to-Sunday target week from an injected instant.
 * Sunday advances to tomorrow. Monday through Saturday uses the current Monday.
 *
 * @param {Date} now
 * @returns {{ weekStart: string, weekEnd: string }} ISO calendar dates
 */
export function getPerthTargetWeek(now = new Date()) {
  const parts = getPerthDateParts(now)
  const weekday = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[parts.weekday]
  const perthDate = new Date(Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day)))
  const offsetToMonday = weekday === 0 ? 1 : 1 - weekday
  const weekStartDate = addUtcDays(perthDate, offsetToMonday)

  return {
    weekStart: toUtcIsoCalendarDate(weekStartDate),
    weekEnd: toUtcIsoCalendarDate(addUtcDays(weekStartDate, 6)),
  }
}

/** Return the Perth calendar date for a supplied instant. */
export function getPerthCalendarDate(now = new Date()) {
  const parts = getPerthDateParts(now)
  return toIsoCalendarDate(Number(parts.year), Number(parts.month), Number(parts.day))
}

/**
 * Return the newest calendar date for a parsed run with recorded attendance.
 * Invalid, undated, and zero-attendance rows cannot become an email cutoff.
 *
 * @param {Array<{ parsedDate: Date, totalAttendance: number }>} runs
 * @returns {string | null} ISO calendar date
 */
export function getAttendanceCutoff(runs) {
  let newestDate = null

  for (const run of runs ?? []) {
    const date = run?.parsedDate
    if (!(run?.totalAttendance > 0) || !(date instanceof Date) || Number.isNaN(date.getTime())) {
      continue
    }
    if (!newestDate || date.getTime() > newestDate.getTime()) newestDate = date
  }

  if (!newestDate) return null

  // parseRunData creates local-midnight Dates from sheet calendar values, so
  // local getters preserve that source date in every runtime time zone.
  return toIsoCalendarDate(
    newestDate.getFullYear(),
    newestDate.getMonth() + 1,
    newestDate.getDate()
  )
}

/**
 * Format one deterministic plain-text digest, or return null when no content is
 * needed. Candidate validation is repeated here so direct callers cannot bypass
 * the untrusted-name boundary enforced by findUpcomingMilestones().
 *
 * @param {{
 *   candidates: Array<{ name: string, currentRuns: number, milestone: number }>,
 *   weekStart: string,
 *   cutoffDate: string | null,
 * }} input
 * @returns {{ subject: string, body: string } | null}
 */
export function formatMilestoneDigest({ candidates, weekStart, cutoffDate }) {
  if (!Array.isArray(candidates)) throw new Error('Candidates must be an array')
  if (candidates.length === 0) return null
  if (typeof cutoffDate !== 'string') throw new Error('Attendance cutoff is unavailable')

  const sortedCandidates = candidates.map((candidate) => {
    assertSafeCandidateName(candidate?.name)
    if (!Number.isInteger(candidate?.milestone) || candidate.milestone <= 0) {
      throw new Error('Candidate milestone is invalid')
    }
    return { ...candidate }
  }).sort(compareCandidates)

  const formattedWeekStart = formatIsoCalendarDate(weekStart, 'Target week is invalid')
  const formattedCutoff = formatIsoCalendarDate(cutoffDate, 'Attendance cutoff is unavailable')
  const count = sortedCandidates.length
  const lines = sortedCandidates.map(
    ({ name, milestone }) => `- ${name} — ${formatOrdinal(milestone)} run`
  )
  const body = [
    `${count} ${count === 1 ? 'runner is' : 'runners are'} one recorded run from a milestone:`,
    '',
    ...lines,
    '',
    `Based on FCTC attendance recorded through ${formattedCutoff}.`,
  ].join('\n')

  if (new TextEncoder().encode(body).byteLength > MAX_BODY_BYTES) {
    throw new Error('Milestone digest exceeds 64 KiB')
  }

  return {
    subject: `FCTC milestone runs — week of ${formattedWeekStart}`,
    body,
  }
}

function assertSafeCandidateName(name) {
  if (typeof name !== 'string' || name.length === 0 || UNSAFE_NAME_PATTERN.test(name)) {
    throw new Error('Candidate name is unsafe')
  }
  if ([...name].length > MAX_NAME_CODE_POINTS) {
    throw new Error('Candidate name is too long')
  }
}

function compareCandidates(left, right) {
  const milestoneDifference = left.milestone - right.milestone
  if (milestoneDifference !== 0) return milestoneDifference

  const leftNormalized = left.name.normalize('NFKC')
  const rightNormalized = right.name.normalize('NFKC')
  return NAME_COLLATOR.compare(leftNormalized, rightNormalized) ||
    compareCodePoints(leftNormalized, rightNormalized) ||
    compareCodePoints(left.name, right.name)
}

function compareCodePoints(left, right) {
  if (left === right) return 0
  return left < right ? -1 : 1
}

function formatOrdinal(value) {
  const lastTwoDigits = value % 100
  if (lastTwoDigits >= 11 && lastTwoDigits <= 13) return `${value}th`

  return `${value}${{ 1: 'st', 2: 'nd', 3: 'rd' }[value % 10] ?? 'th'}`
}

function formatIsoCalendarDate(value, errorMessage) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value ?? '')
  if (!match) throw new Error(errorMessage)

  const [, yearText, monthText, dayText] = match
  const year = Number(yearText)
  const month = Number(monthText)
  const day = Number(dayText)
  const date = new Date(Date.UTC(year, month - 1, day))

  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() + 1 !== month ||
    date.getUTCDate() !== day
  ) {
    throw new Error(errorMessage)
  }

  return DISPLAY_DATE_FORMATTER.format(date)
}

function addUtcDays(date, days) {
  const result = new Date(date)
  result.setUTCDate(result.getUTCDate() + days)
  return result
}

function getPerthDateParts(now) {
  if (!(now instanceof Date) || Number.isNaN(now.getTime())) {
    throw new Error('Clock must be a valid Date')
  }

  return Object.fromEntries(
    PERTH_DATE_FORMATTER.formatToParts(now).map(({ type, value }) => [type, value])
  )
}

function toUtcIsoCalendarDate(date) {
  return toIsoCalendarDate(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate())
}

function toIsoCalendarDate(year, month, day) {
  return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
}
