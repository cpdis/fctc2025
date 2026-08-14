import {
  calculateMilestoneChance,
  calculateWeightedAttendanceRate,
} from './milestoneForecast.js'

const PERTH_TIME_ZONE = 'Australia/Perth'
const MAX_NAME_CODE_POINTS = 200
const MAX_BODY_BYTES = 64 * 1024
const MAX_HTML_BYTES = 256 * 1024
const MILESTONE_COLORS = ['#d75b77', '#e8442c', '#ff7a30']
const FORECAST_WEEKDAYS = ['Mon', 'Wed', 'Fri']
const FORECAST_LABELS = new Set(['Very likely', 'Likely', 'Possible'])

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

const EMAIL_DATE_FORMATTER = new Intl.DateTimeFormat('en-AU', {
  timeZone: 'UTC',
  day: 'numeric',
  month: 'long',
  year: 'numeric',
})

// C0/C1 controls, explicit line separators, and bidirectional embedding,
// override, and isolate controls can change or conceal plain-text email content.
const UNSAFE_NAME_PATTERN = /[\p{Cc}\u2028\u2029\u202a-\u202e\u2066-\u2069]/u

/**
 * Find members likely to reach their next positive multiple of 50 this week.
 *
 * @param {Record<string, { name: string, totalRuns: number }>} memberTotals
 * @param {Array<Object>} runs parsed run records from every registered season
 * @param {string | null} cutoffDate inclusive ISO attendance cutoff
 * @returns {Array<{
 *   name: string,
 *   currentRuns: number,
 *   milestone: number,
 *   runsNeeded: number,
 *   chance: number,
 *   label: string,
 * }>}
 */
export function findUpcomingMilestones(memberTotals, runs = [], cutoffDate = null) {
  const candidates = []

  for (const member of Object.values(memberTotals ?? {})) {
    const currentRuns = member?.totalRuns
    if (!Number.isSafeInteger(currentRuns) || currentRuns < 0) continue

    const milestone = (Math.floor(currentRuns / 50) + 1) * 50
    if (!Number.isSafeInteger(milestone) || milestone <= 0) continue

    const runsNeeded = milestone - currentRuns
    if (runsNeeded > FORECAST_WEEKDAYS.length) continue

    const weekdayRates = getMemberWeekdayRates(member.name, runs, cutoffDate)
    const chance = calculateMilestoneChance(weekdayRates, runsNeeded)
    const label = getMilestoneForecastLabel(chance, runsNeeded)
    if (!label) continue

    assertSafeCandidateName(member.name)
    candidates.push({ name: member.name, currentRuns, milestone, runsNeeded, chance, label })
  }

  return candidates.sort(compareCandidates)
}

/** Convert raw forecast chance to its plain confidence label and inclusion decision. */
export function getMilestoneForecastLabel(chance, runsNeeded) {
  if (!Number.isFinite(chance) || chance < 0 || chance > 1) {
    throw new Error('Milestone chance must be a finite probability')
  }
  if (!Number.isInteger(runsNeeded) || runsNeeded < 1 || runsNeeded > 3) {
    throw new Error('Runs needed must be an integer from 1 to 3')
  }

  if (chance >= 0.8) return 'Very likely'
  if (chance >= 0.5) return 'Likely'
  return runsNeeded === 1 ? 'Possible' : null
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
 * Format one deterministic text and HTML digest, or return null when no content
 * is needed. Candidate validation is repeated here so direct callers cannot
 * bypass the untrusted-name boundary enforced by findUpcomingMilestones().
 *
 * @param {{
 *   candidates: Array<{
 *     name: string,
 *     currentRuns?: number,
 *     milestone: number,
 *     runsNeeded: number,
 *     chance?: number,
 *     label: string,
 *   }>,
 *   weekStart: string,
 *   cutoffDate: string | null,
 * }} input
 * @returns {{ subject: string, body: string, html: string } | null}
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
    if (!Number.isInteger(candidate?.runsNeeded) || candidate.runsNeeded < 1 ||
        candidate.runsNeeded > FORECAST_WEEKDAYS.length) {
      throw new Error('Candidate runs needed is invalid')
    }
    if (!FORECAST_LABELS.has(candidate?.label)) {
      throw new Error('Candidate label is invalid')
    }
    return {
      name: candidate.name,
      milestone: candidate.milestone,
      runsNeeded: candidate.runsNeeded,
      label: candidate.label,
    }
  }).sort(compareCandidates)

  const formattedWeekStart = formatIsoCalendarDate(weekStart, 'Target week is invalid')
  const formattedCutoff = formatIsoCalendarDate(cutoffDate, 'Attendance cutoff is unavailable')
  const count = sortedCandidates.length
  const lines = sortedCandidates.map(
    ({ name, milestone, runsNeeded, label }) => (
      `- ${name} — ${formatOrdinal(milestone)} run — ${label} · needs ${formatRunNeed(runsNeeded)}`
    )
  )
  const body = [
    `${count} ${count === 1 ? 'runner' : 'runners'} could reach a milestone this week:`,
    '',
    ...lines,
    '',
    `Based on FCTC attendance recorded through ${formattedCutoff}.`,
  ].join('\n')

  if (new TextEncoder().encode(body).byteLength > MAX_BODY_BYTES) {
    throw new Error('Milestone digest exceeds 64 KiB')
  }

  const html = formatMilestoneHtml({
    candidates: sortedCandidates,
    formattedWeekStart: formatIsoCalendarDate(
      weekStart,
      'Target week is invalid',
      EMAIL_DATE_FORMATTER
    ).toUpperCase(),
    formattedCutoff,
  })

  if (new TextEncoder().encode(html).byteLength > MAX_HTML_BYTES) {
    throw new Error('Milestone HTML exceeds 256 KiB')
  }

  return {
    subject: `FCTC milestone runs — week of ${formattedWeekStart}`,
    body,
    html,
  }
}

/** Build email-client-safe markup with inline styles and no remote assets. */
function formatMilestoneHtml({ candidates, formattedWeekStart, formattedCutoff }) {
  const count = candidates.length
  const intro = count === 1
    ? 'One scoundrel could reach a landmark run this week. Keep an eye out and make some noise.'
    : `${count} scoundrels could reach a landmark run this week. Keep an eye out and make some noise.`
  const preheader = count === 1
    ? 'One FCTC runner is approaching a milestone run this week.'
    : `${count} FCTC runners are approaching milestone runs this week.`
  const rows = candidates.map(({ name, milestone, runsNeeded, label }, index) => {
    const color = MILESTONE_COLORS[index % MILESTONE_COLORS.length]
    const topBorder = index === 0 ? '2px solid #1c1410' : '1px solid #d9d5d1'
    const bottomBorder = index === candidates.length - 1 ? ' border-bottom: 2px solid #1c1410;' : ''

    return `
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width: 100%; border-collapse: collapse; border-top: ${topBorder};${bottomBorder}">
                  <tr>
                    <td class="milestone-number" width="108" valign="middle" style="width: 108px; padding: 24px 0 22px; color: ${color}; font-family: Impact, Haettenschweiler, 'Arial Narrow Bold', sans-serif; font-size: 58px; line-height: 1; font-variant-numeric: tabular-nums;">
                      ${milestone}
                    </td>
                    <td valign="middle" style="padding: 24px 0 22px 20px;">
                      <p class="member-name" style="margin: 0; color: #1c1410; font-family: Arial, Helvetica, sans-serif; font-size: 24px; font-weight: 700; line-height: 30px;">
                        ${escapeHtml(name)}
                      </p>
                      <p style="margin: 5px 0 0; color: #6f5f53; font-family: 'Courier New', Courier, monospace; font-size: 12px; line-height: 18px; letter-spacing: 0.8px; text-transform: uppercase;">
                        ${label} &middot; needs ${formatRunNeed(runsNeeded)} for their ${formatOrdinal(milestone)} run
                      </p>
                    </td>
                  </tr>
                </table>`
  }).join('')

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>FCTC milestones</title>
    <style>
      html, body { margin: 0; padding: 0; background: #ffffff; }
      table { border-collapse: collapse; }
      @media only screen and (max-width: 640px) {
        .email-shell { width: 100% !important; border-right: 0 !important; border-left: 0 !important; }
        .email-pad { padding-right: 24px !important; padding-left: 24px !important; }
        .headline { font-size: 48px !important; }
        .milestone-number { width: 82px !important; font-size: 48px !important; }
        .member-name { font-size: 21px !important; }
      }
    </style>
  </head>
  <body style="margin: 0; padding: 0; background: #ffffff; color: #1c1410; font-family: Arial, Helvetica, sans-serif; -webkit-font-smoothing: antialiased;">
    <div style="display: none; max-height: 0; overflow: hidden; opacity: 0; color: transparent; mso-hide: all;">
      ${preheader}
    </div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width: 100%; background: #ffffff; border-collapse: collapse;">
      <tr>
        <td align="center" style="padding: 32px 16px;">
          <table class="email-shell" role="presentation" width="620" cellspacing="0" cellpadding="0" border="0" style="width: 100%; max-width: 620px; background: #ffffff; border: 1px solid #e8e1d8; border-collapse: collapse;">
            <tr>
              <td>
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" aria-hidden="true" style="width: 100%; border-collapse: collapse;">
                  <tr>
                    <td width="34%" height="9" style="width: 34%; height: 9px; background: #ffd23f; font-size: 0; line-height: 0;">&nbsp;</td>
                    <td width="33%" height="9" style="width: 33%; height: 9px; background: #ff7a30; font-size: 0; line-height: 0;">&nbsp;</td>
                    <td width="33%" height="9" style="width: 33%; height: 9px; background: #e8442c; font-size: 0; line-height: 0;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td class="email-pad" style="padding: 30px 42px 0;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width: 100%; border-collapse: collapse;">
                  <tr>
                    <td style="font-family: Impact, Haettenschweiler, 'Arial Narrow Bold', sans-serif; font-size: 27px; letter-spacing: 0.4px; color: #1c1410; text-transform: uppercase;">
                      FC<span style="color: #d75b77;">TC</span>
                    </td>
                    <td align="right" style="font-family: 'Courier New', Courier, monospace; font-size: 12px; line-height: 18px; letter-spacing: 1px; color: #6f5f53; text-transform: uppercase;">
                      Perth, WA
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td class="email-pad" style="padding: 54px 42px 0;">
                <p style="margin: 0 0 12px; font-family: 'Courier New', Courier, monospace; font-size: 13px; line-height: 20px; letter-spacing: 1.4px; color: #d75b77; text-transform: uppercase;">
                  WEEK OF ${formattedWeekStart}
                </p>
                <h1 class="headline" style="max-width: 510px; margin: 0; color: #1c1410; font-family: Impact, Haettenschweiler, 'Arial Narrow Bold', sans-serif; font-size: 64px; font-weight: 400; line-height: 0.94; letter-spacing: 0.2px; text-transform: uppercase;">
                  MILESTONES<br>AHEAD
                </h1>
                <p style="max-width: 475px; margin: 25px 0 0; color: #5c4f43; font-family: Arial, Helvetica, sans-serif; font-size: 17px; line-height: 27px;">
                  ${intro}
                </p>
              </td>
            </tr>

            <tr>
              <td class="email-pad" style="padding: 43px 42px 0;">
                ${rows}
              </td>
            </tr>

            <tr>
              <td class="email-pad" style="padding: 20px 42px 0; color: #6f5f53; font-family: 'Courier New', Courier, monospace; font-size: 11px; line-height: 18px; letter-spacing: 0.7px; text-transform: uppercase;">
                Attendance recorded through ${formattedCutoff}.
              </td>
            </tr>

            <tr>
              <td class="email-pad" style="padding: 32px 42px 0;">
                <table role="presentation" cellspacing="0" cellpadding="0" border="0" style="border-collapse: collapse;">
                  <tr>
                    <td style="background: #1c1410;">
                      <a href="https://fctc.fun/dashboard" style="display: inline-block; padding: 13px 18px; color: #ffffff; font-family: 'Courier New', Courier, monospace; font-size: 13px; font-weight: 700; line-height: 18px; letter-spacing: 0.8px; text-decoration: none; text-transform: uppercase;">
                        View dashboard&nbsp;&nbsp;&rarr;
                      </a>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td class="email-pad" style="padding: 54px 42px 34px;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width: 100%; border-top: 1px solid #d9d5d1; border-collapse: collapse;">
                  <tr>
                    <td style="padding-top: 21px; color: #6f5f53; font-family: 'Courier New', Courier, monospace; font-size: 11px; line-height: 18px; letter-spacing: 0.8px; text-transform: uppercase;">
                      FCTC &mdash; Perth, WA
                    </td>
                    <td align="right" style="padding-top: 21px; color: #d75b77; font-family: 'Courier New', Courier, monospace; font-size: 11px; font-weight: 700; line-height: 18px; letter-spacing: 0.8px; text-transform: uppercase;">
                      Amen scoundrels
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`
}

function assertSafeCandidateName(name) {
  if (typeof name !== 'string' || name.length === 0 || UNSAFE_NAME_PATTERN.test(name)) {
    throw new Error('Candidate name is unsafe')
  }
  if ([...name].length > MAX_NAME_CODE_POINTS) {
    throw new Error('Candidate name is too long')
  }
}

/** Build fixed Monday, Wednesday, and Friday rates from eligible parsed rows. */
function getMemberWeekdayRates(name, runs, cutoffDate) {
  const cutoffKey = parseOptionalIsoCalendarDate(cutoffDate)
  if (!Array.isArray(runs) || cutoffKey === null) return [0, 0, 0]

  const completedRuns = runs
    .map((run, inputIndex) => ({ run, inputIndex }))
    .filter(({ run }) => isCompletedRunThroughCutoff(run, cutoffKey))

  const firstAttendance = completedRuns
    .filter(({ run }) => run.attendance?.[name] === true)
    .reduce((earliest, entry) => {
      if (!earliest || entry.run.parsedDate < earliest.run.parsedDate) return entry
      return earliest
    }, null)

  if (!firstAttendance) return [0, 0, 0]

  return FORECAST_WEEKDAYS.map((weekday) => {
    const history = completedRuns
      .filter(({ run }) => (
        run.parsedDate >= firstAttendance.run.parsedDate && run.dayOfWeek === weekday
      ))
      .sort((left, right) => (
        right.run.parsedDate - left.run.parsedDate || right.inputIndex - left.inputIndex
      ))
      .map(({ run }) => run.attendance?.[name] === true)

    return calculateWeightedAttendanceRate(history) ?? 0
  })
}

function isCompletedRunThroughCutoff(run, cutoffKey) {
  return Number.isFinite(run?.totalAttendance) &&
    run.totalAttendance > 0 &&
    run.parsedDate instanceof Date &&
    !Number.isNaN(run.parsedDate.getTime()) &&
    getLocalCalendarDateKey(run.parsedDate) <= cutoffKey
}

function parseOptionalIsoCalendarDate(value) {
  if (value === null || value === undefined) return null

  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!match) throw new Error('Attendance cutoff is invalid')

  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const date = new Date(Date.UTC(year, month - 1, day))

  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() + 1 !== month ||
    date.getUTCDate() !== day
  ) {
    throw new Error('Attendance cutoff is invalid')
  }

  return year * 10_000 + month * 100 + day
}

function getLocalCalendarDateKey(date) {
  return date.getFullYear() * 10_000 + (date.getMonth() + 1) * 100 + date.getDate()
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

function formatRunNeed(runsNeeded) {
  return `${runsNeeded} ${runsNeeded === 1 ? 'run' : 'runs'}`
}

function formatIsoCalendarDate(value, errorMessage, formatter = DISPLAY_DATE_FORMATTER) {
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

  return formatter.format(date)
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character])
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
