import { resolveYear } from '../config/years.js'

// Where the dashboard is mounted, and how every link inside it is built (KTD9).
//
// fctc.fun proxies this app under /dashboard (the hub's vercel.json rewrites
// /dashboard/:path+ to the app's root), while the app's own domain serves it
// at the root. Links must stay under the mount point, or a click on fctc.fun
// falls out of the proxy and lands on the hub (review finding 13).
//
// The view lives in the query string: `year` (a season, or "all") and the
// run log's filters. A run link carries the view so the run page knows its
// way back, but the run itself resolves from its id alone (KTD4):
//
//   /dashboard?year=2025&type=Drift                          the view
//   /dashboard/run/2025-12-31-intervals?year=2025&type=Drift  a run opened from it
//   /dashboard?year=2025&type=Drift                          its back link

/** The query params the run log owns (R15). A year switch drops them. */
export const RUN_LOG_FILTERS = ['type', 'location', 'month', 'q']

// A run id starts with the run's ISO date (KTD4), so its first four digits
// name the season it belongs to. Old numeric index links never match.
const RUN_ID_PATTERN = /^(\d{4})-\d{2}-\d{2}-/

/**
 * @param {string} pathname - the current location's pathname
 * @returns {'/dashboard' | ''} the mount point to prefix app links with
 */
export function dashboardBasePath(pathname) {
  return pathname === '/dashboard' || pathname.startsWith('/dashboard/') ? '/dashboard' : ''
}

// The mount point's own page: "/dashboard" under the hub, "/" at the root.
function dashboardRoot(base) {
  return base || '/'
}

// "?year=…" then whichever run-log filters `params` holds, in a fixed order.
// The year is always written (resolved, so a missing or bad one becomes the
// latest season), and anything else in `params` is not part of the view.
function viewQuery(params) {
  const query = new URLSearchParams({ year: String(resolveYear(params.get('year'))) })
  for (const key of RUN_LOG_FILTERS) {
    const value = params.get(key)
    if (value) query.set(key, value)
  }
  return `?${query}`
}

/**
 * The dashboard link for a season, with no filters: "/dashboard?year=2025".
 *
 * @param {'/dashboard' | ''} base - from dashboardBasePath
 * @param {number|'all'} year - the selected season
 */
export function dashboardHref(base, year) {
  return `${dashboardRoot(base)}?${new URLSearchParams({ year: String(year) })}`
}

/**
 * A run's link, keeping the view it was opened from:
 * "/dashboard/run/2025-12-31-intervals?year=all&type=Intervals".
 *
 * @param {'/dashboard' | ''} base - from dashboardBasePath
 * @param {string} runId - the run's stable id
 * @param {URLSearchParams} params - the current view's query
 */
export function runHref(base, runId, params) {
  return `${base}/run/${encodeURIComponent(runId)}${viewQuery(params)}`
}

/**
 * A run page's link back to the view it was opened from, filters included,
 * so Back restores the run log as the viewer left it.
 *
 * @param {'/dashboard' | ''} base - from dashboardBasePath
 * @param {URLSearchParams} params - the run page's query
 */
export function backHref(base, params) {
  return `${dashboardRoot(base)}${viewQuery(params)}`
}

/**
 * The query for a year switch: a new season is a new view, so the run-log
 * filters go (AE7) and any other param stays. The input is left untouched.
 *
 * @param {URLSearchParams} params - the current query
 * @param {number|'all'} year - the season switched to
 * @returns {URLSearchParams}
 */
export function yearSwitchParams(params, year) {
  const next = new URLSearchParams(params)
  for (const key of RUN_LOG_FILTERS) next.delete(key)
  next.set('year', String(year))
  return next
}

/**
 * Resolve a run id inside its own season, whatever season the view shows
 * (KTD4): a 2025 id opened from All time or from 2026 is that 2025 run.
 *
 * @param {Record<number, { runs: Array<{ id: string }> }>} seasons - parsed
 *   seasons keyed by year
 * @param {string|undefined} runId - the id from the URL
 * @returns {object|null} the run, or null for an unknown or numeric id
 */
export function findRun(seasons, runId) {
  const match = RUN_ID_PATTERN.exec(runId ?? '')
  if (!match) return null
  return seasons[match[1]]?.runs.find((run) => run.id === runId) ?? null
}
