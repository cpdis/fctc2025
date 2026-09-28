/**
 * Club-day, streak and milestone rules (R4, R5), shared by every dashboard view.
 *
 * A club day is a date on one of its season's official club weekdays (see
 * clubWeekdays in ../config/years.js) with at least one run. A member makes a
 * club day by running any run that day, so the Half and the 10k on Mon 26 Jan
 * 2026 are one club day. A run on any other day is a special (the Sat Pub Run,
 * the Sun Xmas races, 2025's Invasion Day Monday): it never adds to or breaks
 * a streak.
 *
 *   club days    Mon 21  Wed 23  Fri 25  (Sat 26 Pub Run: not a club day)
 *   Ann made       x       .       x     -> current 1 from Fri 25, best 1
 *   Bob made       x       x       x     -> current 3 from Mon 21, best 3
 *
 * A member's current streak is the number of consecutive most-recent club days
 * they made. For a finished season that is its value on the last club day ("at
 * season end"). All time is the club days of every season in date order, each
 * season with its own weekdays, so a streak running to Wed 31 Dec 2025 carries
 * on into Fri 2 Jan 2026.
 *
 * The functions are pure and free of npm dependencies so plain Node (the parity
 * fixture script, the weekly digest) can import them. The Swift kit mirrors the
 * same rules, and the golden parity fixtures keep the two stacks in step.
 */
import { clubWeekdays } from '../config/years.js'
import { isoDate } from './runLabels.js'

// Calendar order, so per-weekday counts read Mon, Wed, Fri whatever day the
// season opened on.
const WEEKDAY_ORDER = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

// Milestone rule, copied from the app's MilestoneBoard (Swift): landmarks every
// 50 runs, nobody more than 10 runs out, the closest 3 plus anyone tied with 3rd.
const MILESTONE_STEP = 50
const MILESTONE_CEILING = 10
const MILESTONE_PLACES = 3

/**
 * Build a view's club days, oldest first.
 *
 * @param {Array} runs - parsed runs from one season or several (All time);
 *   each needs `parsedDate`, `dayOfWeek` and `attendees`
 * @param {(year: number) => readonly string[]} [weekdaysFor] - a season's club
 *   weekdays; tests pin it, callers use the season table
 * @returns {Array<{ date: string, weekday: string, runs: Array, attendees: Set<string> }>}
 *   `date` is the local YYYY-MM-DD, `runs` are that day's runs in sheet order,
 *   `attendees` is everyone who ran any of them
 */
export function buildClubDays(runs, weekdaysFor = clubWeekdays) {
  const byDate = new Map()
  for (const run of runs ?? []) {
    // Each run is judged by its own season's weekdays, which is what keeps
    // 2025's Monday runs specials inside All time.
    if (!weekdaysFor(run.parsedDate.getFullYear()).includes(run.dayOfWeek)) continue

    const date = isoDate(run.parsedDate)
    let day = byDate.get(date)
    if (!day) {
      day = { date, weekday: run.dayOfWeek, runs: [], attendees: new Set() }
      byDate.set(date, day)
    }
    day.runs.push(run)
    for (const name of run.attendees) day.attendees.add(name)
  }
  return [...byDate.values()].sort((a, b) => compareStrings(a.date, b.date))
}

/**
 * One member's record over a list of club days (from buildClubDays).
 *
 * @param {Array} days - club days, oldest first
 * @param {string} name - member name as the parser reports it
 * @returns {{
 *   made: number,
 *   madeByWeekday: Record<string, number>,
 *   current: number,
 *   currentFrom: string | null,
 *   best: number,
 *   bestFrom: string | null,
 *   bestTo: string | null,
 * }}
 *   `madeByWeekday` has a key, zero included, for every weekday that has club
 *   days, in Mon..Sun order. Dates are ISO; they are null when the streak is 0.
 *   Of two equally long best streaks, the earlier one is kept.
 */
export function memberClubDays(days, name) {
  const weekdays = new Set(days.map((day) => day.weekday))
  const madeByWeekday = {}
  for (const weekday of WEEKDAY_ORDER) {
    if (weekdays.has(weekday)) madeByWeekday[weekday] = 0
  }

  let made = 0
  let streak = 0
  let best = 0
  let bestEnd = -1
  days.forEach((day, i) => {
    if (!day.attendees.has(name)) {
      streak = 0
      return
    }
    made += 1
    madeByWeekday[day.weekday] += 1
    streak += 1
    // Strictly longer only, so the first of two equal streaks wins.
    if (streak > best) {
      best = streak
      bestEnd = i
    }
  })

  // The streak still open after the last club day is the current one.
  const current = streak
  return {
    made,
    madeByWeekday,
    current,
    currentFrom: current ? days[days.length - current].date : null,
    best,
    bestFrom: best ? days[bestEnd - best + 1].date : null,
    bestTo: best ? days[bestEnd].date : null,
  }
}

/**
 * The next landmark after a lifetime run count. Someone sitting exactly on a
 * landmark is already past it, so 100 runs points at 150, never at 100.
 *
 * @param {number} runs
 * @returns {number}
 */
export function nextMilestone(runs) {
  return (Math.floor(runs / MILESTONE_STEP) + 1) * MILESTONE_STEP
}

/**
 * Who is near a landmark run, closest first (the app's MilestoneBoard rule).
 *
 * Members 10 or fewer runs from their next multiple of 50 qualify; the closest
 * 3 are kept, plus anyone tied with the 3rd, so a tie is never split. Members
 * with no runs never qualify.
 *
 * @param {Array<{ name: string, runs: number }>} totals - all-time run counts
 *   through the latest run, in any order
 * @returns {Array<{ name: string, runs: number, milestone: number, runsNeeded: number }>}
 */
export function milestoneShortlist(totals) {
  const eligible = (totals ?? [])
    .filter(({ runs }) => runs > 0)
    .map(({ name, runs }) => {
      const milestone = nextMilestone(runs)
      return { name, runs, milestone, runsNeeded: milestone - runs }
    })
    .filter(({ runsNeeded }) => runsNeeded <= MILESTONE_CEILING)
    // Name breaks the tie so the order is stable between refreshes.
    .sort((a, b) => a.runsNeeded - b.runsNeeded || compareStrings(a.name, b.name))

  if (eligible.length <= MILESTONE_PLACES) return eligible
  const cut = eligible[MILESTONE_PLACES - 1].runsNeeded
  return eligible.filter(({ runsNeeded }) => runsNeeded <= cut)
}

/** Plain string order (not locale collation), so every machine sorts alike. */
function compareStrings(a, b) {
  return a < b ? -1 : a > b ? 1 : 0
}
