import { ALL_TIME, YEAR_LIST, isAllTime } from '../../config/years'
import { formatDay } from './format'

// The year control reads left to right in time, as in the mockup: every
// season oldest first, then "All time".
const SEASON_OPTIONS = [
  ...[...YEAR_LIST].reverse().map((year) => ({ value: year, label: String(year) })),
  { value: ALL_TIME, label: 'All time' },
]

/**
 * A run for the meta row: when, where and what, already normalized.
 * @typedef {{ date: Date, location: string, type: string }} MetaRun
 */

/**
 * The title band: kicker, the season heading ("The 2026" in ink, "Season" in
 * pink), the year segmented control, and the meta row (updated, last run,
 * next run). A meta item with no value is left out.
 *
 * @param {object} props
 * @param {number|'all'} props.year - the selected season
 * @param {(year: number|'all') => void} props.onSelectYear
 * @param {Date|null} [props.updatedAt] - when the data last synced
 * @param {MetaRun|null} [props.lastRun]
 * @param {MetaRun|null} [props.nextRun]
 */
export default function SeasonTitle({ year, onSelectYear, updatedAt, lastRun, nextRun }) {
  const [lead, accent] = isAllTime(year) ? ['All', 'time'] : [`The ${year}`, 'Season']

  const meta = [
    updatedAt && ['Updated', formatDay(updatedAt)],
    lastRun && ['Last run', describeRun(lastRun)],
    nextRun && ['Next', describeRun(nextRun)],
  ].filter(Boolean)

  return (
    <>
      <section className="title">
        <div>
          <p className="kicker mono soft">Season dashboard</p>
          {/* The space before <br> keeps the accessible name "The 2026 Season". */}
          <h1 className="display">
            {lead} <br />
            <span className="pink">{accent}</span>
          </h1>
        </div>
        <div className="years mono" role="group" aria-label="Season">
          {SEASON_OPTIONS.map((option) => (
            <button
              key={option.value}
              type="button"
              aria-pressed={option.value === year}
              onClick={() => onSelectYear(option.value)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </section>
      {meta.length > 0 && (
        <div className="meta mono">
          {meta.map(([label, value]) => (
            <span key={label}>
              <b>{label}</b> {value}
            </span>
          ))}
        </div>
      )}
    </>
  )
}

// "Fri 25 Sep · MSBB River Loop"
function describeRun(run) {
  return `${formatDay(run.date)} · ${run.location} ${run.type}`
}
