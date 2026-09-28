import { useEffect, useMemo, useState } from 'react'
import { Link, useLocation, useNavigate, useNavigationType, useSearchParams } from 'react-router-dom'
import { formatDay, formatNumber, monthName } from '../Poster/format'
import { compareNames, monthAxis } from '../../utils/dashboardMetrics'
import { dashboardBasePath, runHref, RUN_LOG_FILTERS } from '../../utils/dashboardPaths'
import { monthKey } from '../../utils/runLabels'
import { useExpandableRows } from '../../utils/useExpandableRows'
import RunTag from './RunTag'
import ShowMoreButton from './ShowMoreButton'

// Rows shown before "Show all N runs" (the approved mockup).
const COLLAPSED_ROWS = 10

/**
 * The Run log section (R15): every run of the view, newest first, with its own type,
 * location, month and search filters. The filters live in the URL, so a run
 * link carries them and Back restores them (KTD9); a year switch drops them
 * (yearSwitchParams). They filter this table only: the log takes the view's
 * runs as a prop and never writes back, so no headline number moves.
 *
 *   ?year=2026&location=Drift&q=aaron   Drift runs in 2026 that Aaron ran
 *
 * A filter value the view does not offer (a hand-edited or stale link) is
 * ignored, so each select always shows the filter that actually applies.
 *
 * @param {{ runs: Array }} props - the view's parsed runs (one season, or
 *   every season merged for All time), in any order; never mutated
 */
export default function RunLog({ runs }) {
  const [params, setParams] = useSearchParams()
  const base = dashboardBasePath(useLocation().pathname)
  const navigate = useNavigate()

  // Options and search text depend only on the view, so a filter change
  // reuses them.
  const log = useMemo(() => buildLog(runs), [runs])

  const type = offered(params.get('type'), log.types)
  const location = offered(params.get('location'), log.locations)
  const month = offered(params.get('month'), log.months.map((option) => option.value))
  const q = params.get('q') ?? ''

  // Memoized so its identity changes only with the filters: that identity is
  // what re-collapses the list to 10 rows.
  const filtered = useMemo(() => {
    const terms = fold(q).split(/\s+/).filter(Boolean)
    return log.rows
      .filter(
        ({ run, text }) =>
          (!type || run.type === type) &&
          (!location || run.location === location) &&
          (!month || monthKey(run.parsedDate) === month) &&
          terms.every((term) => text.includes(term))
      )
      .map(({ run }) => run)
  }, [log, type, location, month, q])

  const { visible, expanded, canExpand, toggle, total } = useExpandableRows(filtered, COLLAPSED_ROWS, filtered)

  // Filter writes replace the history entry: Back leaves the page instead of
  // stepping back through every keystroke.
  const setFilter = (key, value) => {
    setParams(
      (current) => {
        const next = new URLSearchParams(current)
        if (value) next.set(key, value)
        else next.delete(key)
        return next
      },
      { replace: true }
    )
  }

  const [draft, setDraft] = useSearchDraft(q)
  const search = (value) => {
    setDraft(value)
    setFilter('q', value)
  }

  const clearFilters = () => {
    setDraft('')
    setParams(
      (current) => {
        const next = new URLSearchParams(current)
        for (const key of RUN_LOG_FILTERS) next.delete(key)
        return next
      },
      { replace: true }
    )
  }

  const filtering = Boolean(type || location || month || q.trim())

  return (
    <section className="block" aria-labelledby="run-log">
      <div className="kick">
        <h2 id="run-log" className="display">
          Run log
        </h2>
        <p className="mono">Filters apply to this table only</p>
      </div>

      <div className="log-filters">
        <select className="pick" aria-label="Run type" value={type} onChange={(e) => setFilter('type', e.target.value)}>
          <option value="">All run types</option>
          {log.types.map((value) => (
            <option key={value}>{value}</option>
          ))}
        </select>
        <select
          className="pick"
          aria-label="Location"
          value={location}
          onChange={(e) => setFilter('location', e.target.value)}
        >
          <option value="">All locations</option>
          {log.locations.map((value) => (
            <option key={value}>{value}</option>
          ))}
        </select>
        <select className="pick" aria-label="Month" value={month} onChange={(e) => setFilter('month', e.target.value)}>
          <option value="">All months</option>
          {log.months.map(({ value, label }) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
        <input
          type="search"
          className="pick"
          aria-label="Search runs or runners"
          placeholder="Search runs or runners"
          value={draft}
          onChange={(e) => search(e.target.value)}
        />
      </div>

      {filtered.length === 0 ? (
        <div className="log-empty">
          <p className="display">{filtering ? 'No runs match your filters' : 'No runs logged yet'}</p>
          {filtering && (
            <button type="button" className="more" onClick={clearFilters}>
              Clear filters
            </button>
          )}
        </div>
      ) : (
        <>
          <table className="log">
            <thead>
              <tr>
                <th scope="col">Date</th>
                <th scope="col">Run</th>
                <th scope="col" className="hide-sm">
                  Where
                </th>
                <th scope="col" className="km">
                  Km
                </th>
                <th scope="col">Runners</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((run) => {
                const href = runHref(base, run.id, params)
                return (
                  // The whole row opens the run. The date cell's link is the
                  // keyboard and screen-reader way in, and handles its own
                  // clicks (a cmd-click opens a new tab), so the row skips them.
                  <tr
                    key={run.id}
                    onClick={(e) => {
                      if (!e.target.closest('a')) navigate(href)
                    }}
                  >
                    <td className="mono">
                      <Link to={href}>
                        {formatDay(run.parsedDate)}
                        {/* All time spans seasons, so its dates carry the year
                            (on its own line on a phone). The space sits outside
                            the span so the link's name reads "Wed 31 Dec 2025". */}
                        {log.multiYear && (
                          <>
                            {' '}
                            <span className="yr">{run.parsedDate.getFullYear()}</span>
                          </>
                        )}
                      </Link>
                    </td>
                    <td>
                      <RunTag run={run} />
                      {run.event && <span className="event mono">{run.event}</span>}
                    </td>
                    <td className="hide-sm">{run.location}</td>
                    {/* No recorded distance reads "—", never "0" (finding 12). */}
                    <td className="km">{run.actualKm > 0 ? formatNumber(run.actualKm, 1) : '—'}</td>
                    <td>
                      <RunnerDots members={run.attendees.length} plusOnes={run.plusOnes} />
                      {run.totalAttendance}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
          {canExpand && <ShowMoreButton expanded={expanded} total={total} noun="runs" onClick={toggle} />}
        </>
      )}
    </section>
  )
}

/** One solid dot per member and one hollow dot per +1 (decorative: the count follows). */
function RunnerDots({ members, plusOnes }) {
  return (
    <span className="dots" aria-hidden="true">
      {Array.from({ length: members }, (_, i) => (
        <i key={`m${i}`} />
      ))}
      {Array.from({ length: plusOnes }, (_, i) => (
        <i key={`g${i}`} className="g" />
      ))}
    </span>
  )
}

/**
 * The search box's text. It cannot be bound to `?q` directly: the router
 * applies URL changes in a transition, and a controlled input fed by a
 * transition drops keystrokes and jumps its caret. So the box keeps its own
 * draft and writes each keystroke to `?q` (with replace). A `?q` that arrives
 * any other way (Back, Forward, a year switch) is a new view, and the box
 * adopts it.
 *
 * @param {string} q - the URL's current `?q`
 * @returns {[string, (value: string) => void]}
 */
function useSearchDraft(q) {
  const navigationType = useNavigationType()
  const [draft, setDraft] = useState(q)
  useEffect(() => {
    if (navigationType !== 'REPLACE') setDraft(q)
  }, [q, navigationType])
  return [draft, setDraft]
}

/**
 * Everything the log derives from the view alone.
 *
 * @param {Array} runs - the view's runs
 * @returns {{
 *   types: string[], locations: string[],
 *   months: Array<{ value: string, label: string }>,
 *   multiYear: boolean,
 *   rows: Array<{ run: object, text: string }>,
 * }} `months` follow monthAxis (first to latest run month, "YYYY-MM" values);
 *   their labels and the row dates carry the year when the view spans
 *   several seasons (All time). `rows` are newest first, each with its folded search
 *   text.
 */
function buildLog(runs) {
  const axis = monthAxis(runs)
  const multiYear = axis.length > 0 && axis[0].year !== axis.at(-1).year
  return {
    types: distinct(runs.map((run) => run.type)),
    locations: distinct(runs.map((run) => run.location)),
    months: axis.map(({ key, year, month }) => ({
      value: key,
      label: multiYear ? `${monthName(month)} ${year}` : monthName(month),
    })),
    multiYear,
    // A sorted copy, never the view's own array. The sort is stable, so runs
    // sharing a date keep their sheet order (the Half before the 10k).
    rows: [...runs]
      .sort((a, b) => b.parsedDate - a.parsedDate)
      .map((run) => ({ run, text: searchText(run) })),
  }
}

// What a search matches: the date as shown plus its year ("Wed 31 Dec
// 2025"), the type, the event, the location and every member who ran.
function searchText(run) {
  const date = `${formatDay(run.parsedDate)} ${run.parsedDate.getFullYear()}`
  return fold([date, run.type, run.event, run.location, ...run.attendees].filter(Boolean).join(' '))
}

// Lowercase without accents, so "rene" finds René.
function fold(text) {
  return text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
}

// Unique values, A–Z.
function distinct(values) {
  return [...new Set(values)].sort(compareNames)
}

// The URL's value when the view offers it, else '' (no filter).
function offered(value, options) {
  return value && options.includes(value) ? value : ''
}
