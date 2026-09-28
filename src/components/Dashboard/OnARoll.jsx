import { Fragment } from 'react'
import { formatShortDate, parseIsoDate } from '../Poster/format'

const DAY_NAMES = {
  Mon: 'Monday',
  Tue: 'Tuesday',
  Wed: 'Wednesday',
  Thu: 'Thursday',
  Fri: 'Friday',
  Sat: 'Saturday',
  Sun: 'Sunday',
}

// "Monday, Wednesday and Friday": the Australian list style, as the marquee.
const joinDays = new Intl.ListFormat('en-AU', { style: 'long', type: 'conjunction' })

/**
 * The streak rule in one plain sentence (R10), for the view's club weekdays.
 *
 * @param {string[]} weekdays - three-letter names in calendar order
 */
export function streakRule(weekdays) {
  const days = weekdays.length ? `${joinDays.format(weekdays.map((day) => DAY_NAMES[day]))} ` : ''
  return `A streak counts ${days}club runs in a row. Any run that day counts. Weekend and holiday specials don't add to it or break it.`
}

/**
 * The On a roll panel (R10): the top current club-day streaks as rows of pink
 * squares with the count beside them, the best streaks with their dates, and
 * the rule. A finished season's streaks read "At season end".
 *
 * @param {object} props - onARoll(view) output, plus the view kind
 * @param {Array<{ name: string, streak: number }>} props.current
 * @param {Array<{ name: string, streak: number, from: string, to: string }>} props.bests
 * @param {string[]} props.weekdays
 * @param {boolean} props.finished
 * @param {boolean} [props.allTime] - All time: bests may span seasons, so
 *   they are "Longest streaks" and their dates carry the year
 */
export default function OnARoll({ current, bests, weekdays, finished, allTime = false }) {
  const range = ({ from, to }) =>
    `${formatShortDate(parseIsoDate(from), allTime)} – ${formatShortDate(parseIsoDate(to), allTime)}`

  return (
    <div>
      <div className="panel-h">
        <h3>On a roll</h3>
        <span className="mono soft">{finished ? 'At season end' : 'Current streaks'}</span>
      </div>

      {current.length > 0 ? (
        <ol className="streaks" aria-label="Current streaks, club days in a row">
          {current.map(({ name, streak }) => (
            <li key={name} className="streak">
              <span className="who">{name}</span>
              {/* One square per club day; the count beside it says the same. */}
              <span className="squares" aria-hidden="true">
                {Array.from({ length: streak }, (_, i) => (
                  <i key={i} />
                ))}
              </span>
              <span className="n">{streak}</span>
            </li>
          ))}
        </ol>
      ) : (
        <p className="soft">Nobody is on a streak right now.</p>
      )}

      {bests.length > 0 && (
        <p className="best">
          <span className="mono soft">{allTime ? 'Longest streaks' : 'Season best'}</span>
          <br />
          {bests.map((best, i) => (
            <Fragment key={best.name}>
              {i > 0 && ' · '}
              <b>
                {best.name} {best.streak}
              </b>{' '}
              <span className="soft">({range(best)})</span>
            </Fragment>
          ))}
        </p>
      )}

      <p className="note">{streakRule(weekdays)}</p>
    </div>
  )
}
