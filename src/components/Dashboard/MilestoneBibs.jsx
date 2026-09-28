import { useId } from 'react'

/**
 * Milestones ahead: whoever is close to their next 50 all-time runs, as gold
 * race bibs ("2 to 150 · now 148"). The shortlist comes from
 * milestoneShortlist (utils/clubDays.js) over all-time totals through the
 * latest run, so it is the same list in every view.
 *
 * @param {{ shortlist: Array<{ name: string, runs: number, milestone: number, runsNeeded: number }> }} props
 */
export default function MilestoneBibs({ shortlist }) {
  const headingId = useId()
  return (
    <section className="block" aria-labelledby={headingId}>
      <div className="kick">
        <h2 id={headingId} className="display">
          Milestones ahead
        </h2>
        <p className="mono">All-time runs, next 50</p>
      </div>
      {shortlist.length > 0 ? (
        <ul className="bibs">
          {shortlist.map(({ name, runs, milestone, runsNeeded }) => (
            <li key={name} className="bib">
              <div className="who">{name}</div>
              <div className="to">
                {runsNeeded} to {milestone} · now {runs}
              </div>
            </li>
          ))}
        </ul>
      ) : (
        <p className="soft">No one's close to a milestone yet</p>
      )}
    </section>
  )
}
