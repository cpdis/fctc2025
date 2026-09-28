// Single source of truth for which years the dashboard can show and where each
// year's CSV lives in /public. Adding a future year is one line in YEARS.
// Everything else (LATEST_YEAR, YEAR_LIST, the year switcher UI) derives from it.

export const YEARS = {
  2025: '/data/2025.csv',
  2026: '/data/2026.csv',
}

// Years as numbers, sorted newest-first. Use this to render the switcher.
export const YEAR_LIST = Object.keys(YEARS)
  .map(Number)
  .sort((a, b) => b - a)

// The default year when no (or an invalid) ?year is present: the most recent one.
export const LATEST_YEAR = YEAR_LIST[0]

// Sentinel for the "all time" selection (every year's data combined). Lives in
// the same ?year slot in the URL as a real year, e.g. ?year=all. Kept as a
// distinct string so `resolveYear` can return it without colliding with a year.
export const ALL_TIME = 'all'

// Official club weekdays per season (KTD2), as the sheet's three-letter weekday
// names. A club day is one of these weekdays with at least one run on it; a run
// on any other day is a special and never adds to or breaks a streak. 2025 had
// no official Monday run, so its Invasion Day Monday was a special. A season not
// listed here runs Monday, Wednesday and Friday. The Swift kit mirrors this table.
const DEFAULT_CLUB_WEEKDAYS = Object.freeze(['Mon', 'Wed', 'Fri'])
const CLUB_WEEKDAYS = {
  2025: Object.freeze(['Wed', 'Fri']),
}

/**
 * A season's official club weekdays, in weekday order (frozen; do not edit).
 *
 * @param {number} year - season year
 * @returns {readonly string[]} e.g. ['Mon', 'Wed', 'Fri']
 */
export function clubWeekdays(year) {
  return CLUB_WEEKDAYS[year] ?? DEFAULT_CLUB_WEEKDAYS
}

/** True when a resolved selection is the combined "all time" view. */
export function isAllTime(selection) {
  return selection === ALL_TIME
}

/**
 * Resolve a raw `?year` query value (string | null | undefined) to a valid
 * selection: either a year key that exists in YEARS, or the ALL_TIME sentinel.
 * Anything unknown falls back to LATEST_YEAR.
 *
 * Pure + side-effect free so it can be unit tested directly without rendering App.
 *
 * @param {string|number|null|undefined} rawYear
 * @returns {number|'all'} a key that exists in YEARS, or ALL_TIME
 */
export function resolveYear(rawYear) {
  if (rawYear === ALL_TIME) return ALL_TIME
  const parsed = Number(rawYear)
  if (Number.isInteger(parsed) && parsed in YEARS) {
    return parsed
  }
  return LATEST_YEAR
}
