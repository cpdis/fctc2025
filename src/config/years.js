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

/**
 * Resolve a raw `?year` query value (string | null | undefined) to a valid year
 * that we actually have data for. Anything unknown falls back to LATEST_YEAR.
 *
 * Pure + side-effect free so it can be unit tested directly without rendering App.
 *
 * @param {string|number|null|undefined} rawYear
 * @returns {number} a key that exists in YEARS
 */
export function resolveYear(rawYear) {
  const parsed = Number(rawYear)
  if (Number.isInteger(parsed) && parsed in YEARS) {
    return parsed
  }
  return LATEST_YEAR
}
