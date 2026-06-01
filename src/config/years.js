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

// The full set of options the year switcher offers: every real year (newest
// first) plus "All time" at the end. Each carries the value written to ?year
// and the label shown in the dropdown.
export const YEAR_OPTIONS = [
  ...YEAR_LIST.map((year) => ({ value: year, label: String(year) })),
  { value: ALL_TIME, label: 'All time' },
]

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
