import { formatNumber } from './format'

// Copies of the fact line per half of the track: enough to fill a wide screen,
// so the -50% slide in poster.css never shows a gap.
const REPEATS = 4

const joinNames = new Intl.ListFormat('en-AU', { style: 'long', type: 'conjunction' })

/**
 * Who leads on current streak. Ties share the lead, in the order given.
 *
 * @param {Array<{ name: string, current: number }>} streaks
 * @returns {{ names: string[], current: number }|null} null when nobody is on
 *   a streak
 */
export function streakLeaders(streaks) {
  const current = Math.max(0, ...streaks.map((s) => s.current))
  if (current === 0) return null
  return { names: streaks.filter((s) => s.current === current).map((s) => s.name), current }
}

/**
 * The gold band under the headline numbers: the season's headline facts and
 * whoever is on the longest current streak. Decorative (aria-hidden): the same
 * facts are in the numbers and On a roll. Pauses on hover; still under reduced
 * motion (poster.css).
 *
 * @param {object} props
 * @param {number} props.runs
 * @param {number} props.km - member-kilometres
 * @param {number} props.runners
 * @param {Array<{ name: string, current: number }>} props.streaks - every
 *   member's current streak, any order
 */
export default function Marquee({ runs, km, runners, streaks }) {
  const leaders = streakLeaders(streaks)
  const facts = [
    `${formatNumber(runs)} runs`,
    `${formatNumber(km)} km`,
    `${formatNumber(runners)} runners`,
    leaders && `${joinNames.format(leaders.names)} on ${leaders.current} in a row`,
  ].filter(Boolean)
  const content = `${facts.join(' • ')} • `.repeat(REPEATS)

  return (
    <div className="marquee" aria-hidden="true">
      <div className="track">
        <span>{content}</span>
        <span>{content}</span>
      </div>
    </div>
  )
}
