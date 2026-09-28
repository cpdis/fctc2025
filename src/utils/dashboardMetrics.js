/**
 * Dashboard data builders (KTD8).
 *
 * Pure, side-effect-free derivations over a view: one season from
 * `parseRunData(csvText, year)` or the All time merge from `combineYearData`
 * (see ./dataParser.js). Rendering lives in the chart components; this file is
 * only the data layer.
 *
 *   headline        runs, member-km, runners, per run; same date last season
 *   onARoll         current streaks, season bests, "at season end"
 *   wallModel       every active runner against every run of the view
 *   everyRunTracks  one mark per runner, by club weekday plus Specials
 *   seasonProgress  cumulative member-km against the previous season
 *   monthAxis       first to latest run month, for the run log's month filter
 *
 * Honesty rules baked in here:
 *  - Date-keyed series only contain real run dates. The month filter follows
 *    `monthAxis` (first to latest run month), so months that have not happened
 *    yet never appear, and All time keeps its seasons apart (R6).
 *  - Members who attended nothing in the view are left out of per-member outputs.
 *  - Club days, streaks and specials come from ./clubDays.js, the one copy of
 *    those rules (R4, R5).
 *  - A same-date comparison sets one season against the previous one. All time
 *    spans several seasons, so it never compares.
 */
import { LATEST_YEAR } from '../config/years.js'
import { buildClubDays, memberClubDays, WEEKDAY_ORDER } from './clubDays.js'
import { isoDate } from './runLabels.js'

/**
 * Sort runs chronologically by parsedDate. Runs without a parsedDate are
 * dropped from date-ordered series (we can't honestly place them on a timeline).
 * Returns a new array; does not mutate the input.
 */
function datedRunsSorted(runs) {
  return (runs ?? [])
    .filter((r) => r && r.parsedDate instanceof Date && !Number.isNaN(r.parsedDate.getTime()))
    .slice()
    .sort((a, b) => a.parsedDate - b.parsedDate)
}

/** Local YYYY-MM key for a Date. */
function monthKey(d) {
  return isoDate(d).slice(0, 7)
}

/**
 * monthAxis(runs)
 *
 * @param {Array} runs - data.runs from parseRunData
 * @returns {Array<{ key: string, year: number, month: number }>}
 *
 * Every calendar month from the first dated run to the last, inclusive, keyed
 * YYYY-MM (month is 0-based). The run log's month filter offers these months:
 *
 *   2026 (partial)   Jan ... Sep            stops at the latest run month
 *   2025 (complete)  Jan ... Dec
 *   All time         Jan 2025 ... Sep 2026  seasons stay apart
 *
 * A fixed Jan..Dec list would offer months that have not happened yet, and
 * would fold 2025 and 2026 into the same twelve entries.
 */
export function monthAxis(runs) {
  const sorted = datedRunsSorted(runs)
  if (sorted.length === 0) return []
  const last = sorted[sorted.length - 1].parsedDate
  const cursor = new Date(sorted[0].parsedDate.getFullYear(), sorted[0].parsedDate.getMonth(), 1)
  const axis = []
  while (cursor <= last) {
    axis.push({ key: monthKey(cursor), year: cursor.getFullYear(), month: cursor.getMonth() })
    cursor.setMonth(cursor.getMonth() + 1)
  }
  return axis
}

// ---------------------------------------------------------------------------
// Poster dashboard builders. Each takes a view (one season, or All time) and,
// where it compares, the previous season's parsed data.
//
// Runs are read oldest first. The sort is stable, so runs sharing a date keep
// their sheet order (the Half before the 10k on Mon 26 Jan 2026).
// ---------------------------------------------------------------------------

// Track for runs off the club weekdays: weekend and holiday runs.
const SPECIALS = 'Specials'

// How many runners each On a roll list shows (the approved mockup).
const CURRENT_PLACES = 5
const BEST_PLACES = 3

/** Members with at least one run in the view, in the sheet's column order. */
function activeMembers(view) {
  return view.members.filter((name) => view.memberTotals[name]?.totalRuns > 0)
}

/** Most runs in the view first, then A–Z, so ties read the same on every refresh. */
function byRuns(a, b) {
  return b.runs - a.runs || a.name.localeCompare(b.name, 'en')
}

/**
 * The view's club days and the runs that sit on one. Every other run is a
 * special: it is off its own season's club weekdays (see ./clubDays.js).
 */
function clubCalendar(runs) {
  const days = buildClubDays(runs)
  return { days, clubRuns: new Set(days.flatMap((day) => day.runs)) }
}

/** Member-kilometres: each run's actual km once per attending member, +1s excluded. */
function memberKm(runs) {
  return runs.reduce((sum, run) => sum + run.actualKm * run.attendees.length, 0)
}

/** Days since 1 Jan of the date's own year (1 Jan is 0). UTC keeps DST out of it. */
function dayOfYear(date) {
  const year = date.getFullYear()
  return (Date.UTC(year, date.getMonth(), date.getDate()) - Date.UTC(year, 0, 1)) / 86_400_000
}

/**
 * The previous season lined up against a one-season view, or null when there
 * is nothing fair to compare: no previous season, an empty view, or All time.
 *
 * `sameDate` holds the previous season's runs up to the month and day of the
 * view's latest run. Month and day (not day of year) keep 25 Sep against
 * 25 Sep when only one of the two seasons is a leap year.
 *
 * @param {Array} runs - the view's runs, oldest first
 * @param {Object | null | undefined} previous - the previous season's parsed data
 * @returns {{ year: number, runs: Array, sameDate: Array } | null}
 */
function lineUpPrevious(runs, previous) {
  const previousRuns = datedRunsSorted(previous?.runs)
  if (runs.length === 0 || previousRuns.length === 0) return null
  const latest = runs.at(-1).parsedDate
  // All time runs across several seasons, so it has no single "last year".
  if (runs[0].parsedDate.getFullYear() !== latest.getFullYear()) return null

  const month = latest.getMonth()
  const day = latest.getDate()
  return {
    year: previousRuns[0].parsedDate.getFullYear(),
    runs: previousRuns,
    sameDate: previousRuns.filter(
      ({ parsedDate: d }) => d.getMonth() < month || (d.getMonth() === month && d.getDate() <= day)
    ),
  }
}

/**
 * headline(view, previous)
 *
 * The headline numbers. `perRun` is member attendances ÷ runs (the parser's
 * `avgAttendance`, which leaves +1s out). `vsPrevious` is the previous season
 * on the same date: its runs and member-km up to the month and day of the
 * view's latest run, and the view's lead over it. It is null for All time and
 * when there is no previous season.
 *
 *   2026 view, previous 2025, latest run Fri 25 Sep 2026
 *   -> runs 118, vsPrevious { year: 2025, runs: 80, runsDelta: 38, ... }
 *
 * @param {Object} view - parseRunData or combineYearData output
 * @param {Object | null} [previous] - the previous season's parseRunData output
 * @returns {{
 *   runs: number, memberKm: number, runners: number, perRun: number,
 *   vsPrevious: null | { year: number, runs: number, memberKm: number,
 *                        runsDelta: number, memberKmDelta: number },
 * }}
 */
export function headline(view, previous) {
  const past = lineUpPrevious(datedRunsSorted(view.runs), previous)
  const pastKm = past && memberKm(past.sameDate)
  return {
    runs: view.totalRuns,
    memberKm: view.totalClubKm,
    runners: activeMembers(view).length,
    perRun: view.avgAttendance,
    vsPrevious: past && {
      year: past.year,
      runs: past.sameDate.length,
      memberKm: pastKm,
      runsDelta: view.totalRuns - past.sameDate.length,
      memberKmDelta: view.totalClubKm - pastKm,
    },
  }
}

/**
 * onARoll(view)
 *
 * The On a roll panel (R10): the top 5 current club-day streaks and the top 3
 * season-best streaks with their dates, longest first (ties: more runs, then
 * A–Z). `weekdays` are the club weekdays the view's streaks count, in calendar
 * order, for the rule sentence (2025: Wed, Fri). `finished` is true when the
 * view's latest run is in a season before the latest one, so its streaks are
 * "at season end".
 *
 * @param {Object} view - parseRunData or combineYearData output
 * @returns {{
 *   current: Array<{ name: string, streak: number, from: string }>,
 *   bests: Array<{ name: string, streak: number, from: string, to: string }>,
 *   weekdays: string[],
 *   finished: boolean,
 * }}
 *   Dates are ISO (YYYY-MM-DD). Nobody on a streak of 0 is listed.
 */
export function onARoll(view) {
  const runs = datedRunsSorted(view.runs)
  const { days } = clubCalendar(runs)
  const records = activeMembers(view).map((name) => ({
    name,
    runs: view.memberTotals[name].totalRuns,
    ...memberClubDays(days, name),
  }))

  return {
    current: records
      .filter((r) => r.current > 0)
      .sort((a, b) => b.current - a.current || byRuns(a, b))
      .slice(0, CURRENT_PLACES)
      .map(({ name, current, currentFrom }) => ({ name, streak: current, from: currentFrom })),
    bests: records
      .filter((r) => r.best > 0)
      .sort((a, b) => b.best - a.best || byRuns(a, b))
      .slice(0, BEST_PLACES)
      .map(({ name, best, bestFrom, bestTo }) => ({ name, streak: best, from: bestFrom, to: bestTo })),
    weekdays: WEEKDAY_ORDER.filter((weekday) => days.some((day) => day.weekday === weekday)),
    finished: runs.length > 0 && runs.at(-1).parsedDate.getFullYear() < LATEST_YEAR,
  }
}

/**
 * wallModel(view)
 *
 * The Wall (R11): one row per active member (most runs first, then A–Z), one
 * column per run, oldest first. Each cell says:
 *
 *   ran          the member's cell was "x"
 *   streak       a club-day run they ran inside their current streak
 *   special      the run is off its season's club weekdays (same for the column)
 *   notOnRoster  the member had no column on that run's sheet: in All time,
 *                a 2025 run for Dan B, Deano or René, who joined in 2026
 *
 *   Aaron, current streak 14 from Wed 26 Aug 2026
 *   ... Mon 24 Aug  Wed 26 Aug  ...  Sat 5 Sep (Pub Run)  ...  Fri 25 Sep
 *        ran          streak           ran + special             streak
 *
 * @param {Object} view - parseRunData or combineYearData output
 * @returns {{
 *   columns: Array<{ run: Object, date: string, special: boolean }>,
 *   rows: Array<{ name: string, runs: number, current: number,
 *                 cells: Array<{ ran: boolean, streak: boolean, special: boolean,
 *                                notOnRoster: boolean }> }>,
 * }}
 */
export function wallModel(view) {
  const runs = datedRunsSorted(view.runs)
  const { days, clubRuns } = clubCalendar(runs)
  const columns = runs.map((run) => ({ run, date: isoDate(run.parsedDate), special: !clubRuns.has(run) }))

  const rows = activeMembers(view).map((name) => {
    const { current, currentFrom } = memberClubDays(days, name)
    const cells = columns.map(({ run, date, special }) => {
      const ran = run.attendance[name] === true
      return {
        ran,
        // Every club day from currentFrom on is one the member made, so each
        // club-day run they ran from then on belongs to the current streak.
        streak: ran && !special && current > 0 && date >= currentFrom,
        special,
        notOnRoster: !(name in run.attendance),
      }
    })
    return { name, runs: view.memberTotals[name].totalRuns, current, cells }
  })

  return { columns, rows: rows.sort(byRuns) }
}

/**
 * everyRunTracks(view)
 *
 * The Every run chart (R13): one track per club weekday in the view (Mon..Sun
 * order), then Specials. Runs sharing a date share one column, with one mark
 * per member who ran any of them plus the +1s. Tracks without runs are left
 * out, so 2025 has no Monday track (its Invasion Day Monday is a special).
 *
 * `busiest` is the column with the most members plus +1s (the earlier one on a
 * tie), labelled with its event ("Invasion Day"), else its first run's type.
 * `location` is the track's most common location, for its subtitle.
 *
 * @param {Object} view - parseRunData or combineYearData output
 * @returns {Array<{
 *   name: string,
 *   location: string | null,
 *   columns: Array<{ date: string, runs: Array, members: number, plusOnes: number }>,
 *   averageMembers: number,
 *   busiest: { date: string, label: string, count: number },
 * }>}
 */
export function everyRunTracks(view) {
  const runs = datedRunsSorted(view.runs)
  const { clubRuns } = clubCalendar(runs)

  const runsByTrack = new Map()
  for (const run of runs) {
    const name = clubRuns.has(run) ? run.dayOfWeek : SPECIALS
    if (!runsByTrack.has(name)) runsByTrack.set(name, [])
    runsByTrack.get(name).push(run)
  }

  // Weekday tracks in calendar order; Specials sorts after Sunday.
  const order = (name) => (name === SPECIALS ? WEEKDAY_ORDER.length : WEEKDAY_ORDER.indexOf(name))
  return [...runsByTrack]
    .sort(([a], [b]) => order(a) - order(b))
    .map(([name, trackRuns]) => buildTrack(name, trackRuns))
}

/** One Every run track from its runs, oldest first (see everyRunTracks). */
function buildTrack(name, runs) {
  const byDate = new Map()
  for (const run of runs) {
    const date = isoDate(run.parsedDate)
    if (!byDate.has(date)) byDate.set(date, { date, runs: [], names: new Set(), plusOnes: 0 })
    const column = byDate.get(date)
    column.runs.push(run)
    for (const member of run.attendees) column.names.add(member)
    column.plusOnes += run.plusOnes
  }
  const columns = [...byDate.values()].map(({ names, ...column }) => ({ ...column, members: names.size }))

  const size = (column) => column.members + column.plusOnes
  const busiest = columns.reduce((top, column) => (size(column) > size(top) ? column : top))
  return {
    name,
    location: mostCommon(runs.map((run) => run.location).filter(Boolean)),
    columns,
    averageMembers: columns.reduce((sum, column) => sum + column.members, 0) / columns.length,
    busiest: {
      date: busiest.date,
      label: busiest.runs.find((run) => run.event)?.event ?? busiest.runs[0].type,
      count: size(busiest),
    },
  }
}

/** The most frequent value (the first seen on a tie), or null for none. */
function mostCommon(values) {
  const counts = new Map()
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1)
  let top = null
  for (const [value, count] of counts) if (top === null || count > counts.get(top)) top = value
  return top
}

/**
 * seasonProgress(view, previous)
 *
 * Vs last year (R14): cumulative member-km by day of year for the view's season
 * and the previous one, one point per run date. `previousAtLatest` is the
 * previous season's total up to the month and day of the view's latest run, the
 * other end of the gap the chart labels. Null (the chart hides) for All time
 * and when there is no previous season.
 *
 * @param {Object} view - one season's parseRunData output
 * @param {Object | null} [previous] - the previous season's parseRunData output
 * @returns {null | {
 *   current: { year: number, points: Array<{ date: string, dayOfYear: number, memberKm: number }> },
 *   previous: { year: number, points: Array<{ date: string, dayOfYear: number, memberKm: number }> },
 *   previousAtLatest: number,
 * }}
 */
export function seasonProgress(view, previous) {
  const runs = datedRunsSorted(view.runs)
  const past = lineUpPrevious(runs, previous)
  if (!past) return null
  return {
    current: { year: runs[0].parsedDate.getFullYear(), points: cumulativeMemberKm(runs) },
    previous: { year: past.year, points: cumulativeMemberKm(past.runs) },
    previousAtLatest: memberKm(past.sameDate),
  }
}

/** Running member-km, one point per run date (same-date runs fold into one). */
function cumulativeMemberKm(runs) {
  const points = []
  let total = 0
  for (const run of runs) {
    total += memberKm([run])
    const date = isoDate(run.parsedDate)
    if (points.at(-1)?.date === date) points.at(-1).memberKm = total
    else points.push({ date, dayOfYear: dayOfYear(run.parsedDate), memberKm: total })
  }
  return points
}
