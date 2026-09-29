import { Link, useLocation, useParams, useSearchParams } from 'react-router-dom'
import SiteHeader from '../components/Poster/SiteHeader'
import SiteFooter from '../components/Poster/SiteFooter'
import RunTag from '../components/Dashboard/RunTag'
import { formatDay, formatNumber } from '../components/Poster/format'
import { isAllTime, resolveYear } from '../config/years'
import { backHref, dashboardBasePath, findRun } from '../utils/dashboardPaths'

/**
 * One run's page, at /run/:runId or /dashboard/run/:runId, in the Poster
 * style: the date as the title, the run's type, event and place, its numbers,
 * and who ran (members, then +1s).
 *
 * The run resolves from its id alone, inside the season the id's date names
 * (KTD4), so a 2025 run opened from All time is still that 2025 run. `?year`
 * and the run-log filters only name the view the run was opened from: the
 * Back link returns to it, filters included, and the header's Dashboard link
 * keeps its year. An unknown id, including an old numeric index link, shows
 * "Run not found".
 *
 * @param {{ seasons: Record<number, object> }} props - every parsed season,
 *   keyed by year
 */
export default function RunDetail({ seasons }) {
  const { runId } = useParams()
  const { pathname } = useLocation()
  const [searchParams] = useSearchParams()
  const year = resolveYear(searchParams.get('year'))
  const viewLabel = isAllTime(year) ? 'All Time' : `${year} Season`
  const run = findRun(seasons, runId)

  return (
    <div className="poster">
      <SiteHeader year={year} />

      <main className="wrap run-page">
        <section className="title">
          <div>
            <p className="kicker mono soft">Run log</p>
            {/* The space before <br> keeps the accessible name "Wed 31 Dec 2025". */}
            <h1 className="display">
              {run ? (
                <>
                  {formatDay(run.parsedDate)} <br />
                  <span className="pink">{run.parsedDate.getFullYear()}</span>
                </>
              ) : (
                'Run not found'
              )}
            </h1>
          </div>
          {/* A link, not history.back, so a shared run link opened fresh still
              has somewhere to go. It names the view it returns to. */}
          <Link to={backHref(dashboardBasePath(pathname), searchParams)} className="run-back mono">
            <span aria-hidden="true">← </span>Back to {viewLabel}
          </Link>
        </section>

        {run ? (
          <RunFacts run={run} />
        ) : (
          <p className="run-missing">This link doesn&rsquo;t match any run in the log.</p>
        )}
      </main>

      <SiteFooter seasonLabel={viewLabel} />
    </div>
  )
}

/** The run's meta row, its four numbers and who ran. */
function RunFacts({ run }) {
  const members = run.attendees.length
  // A run with attendance but no recorded km reads "—", never "0" (finding 12).
  const km = run.actualKm > 0 ? run.actualKm : null

  const numbers = [
    { label: 'Runners', value: formatNumber(members) },
    { label: 'Plus ones', value: formatNumber(run.plusOnes) },
    { label: 'Route', value: km ? formatNumber(km, 1) : '—', unit: km && 'km', note: !km && 'No distance logged' },
    // Member-km, as the headline counts it: km once per member, +1s left out.
    {
      label: 'Run together',
      value: km ? formatNumber(km * members, 1) : '—',
      unit: km && 'km',
      note: 'Km × runners, not counting +1s',
    },
  ]

  return (
    <>
      <div className="meta mono">
        <span>
          <b>Run</b> <RunTag run={run} />
        </span>
        {run.event && (
          <span>
            <b>Event</b> {run.event}
          </span>
        )}
        <span>
          <b>Where</b> {run.location}
        </span>
      </div>

      <div className="numbers">
        {numbers.map(({ label, value, unit, note }) => (
          <div key={label} className="num">
            <div className="v">
              {value}
              {unit && <small>{unit}</small>}
            </div>
            <div className="l mono">{label}</div>
            {note && <div className="d">{note}</div>}
          </div>
        ))}
      </div>

      <section className="block" aria-labelledby="who-ran">
        <div className="kick">
          <h2 id="who-ran" className="display">
            Who ran
          </h2>
          <p className="mono">{whoRanSummary(members, run.plusOnes)}</p>
        </div>
        {/* Members in sheet order, then one hollow-dot entry per +1, as the
            run log's dots draw them. */}
        <ul className="runners">
          {run.attendees.map((name) => (
            <li key={name}>
              <i aria-hidden="true" />
              {name}
            </li>
          ))}
          {Array.from({ length: run.plusOnes }, (_, i) => (
            <li key={`+1-${i}`} className="guest">
              <i aria-hidden="true" />
              +1
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}

// "12 runners and 2 plus ones", "1 runner", "3 plus ones". Words, not "+1s":
// the note is set in caps, where "+1S" reads as a typo.
function whoRanSummary(members, plusOnes) {
  const parts = [
    members > 0 && `${members} runner${members === 1 ? '' : 's'}`,
    plusOnes > 0 && `${plusOnes} plus one${plusOnes === 1 ? '' : 's'}`,
  ].filter(Boolean)
  return parts.join(' and ')
}
