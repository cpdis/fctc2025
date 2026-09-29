import { clubWeekdays } from '../../config/years'

/**
 * A special is a run off its own season's club weekdays (the Sat Pub Run,
 * 2025's Invasion Day Monday) or a named event (Xmas, Anzac Day, Good Friday),
 * even when the event falls on a club weekday.
 */
function isSpecial(run) {
  return Boolean(run.event) || !clubWeekdays(run.parsedDate.getFullYear()).includes(run.dayOfWeek)
}

/**
 * A run's normalized type as a Poster tag: ink outline for a club run, gold
 * for a special. The gold is visual only, so screen readers hear "special".
 *
 * @param {{ run: { type: string, event: string|null, parsedDate: Date, dayOfWeek: string } }} props
 */
export default function RunTag({ run }) {
  const special = isSpecial(run)
  return (
    <>
      <span className={special ? 'tag sp' : 'tag'}>{run.type}</span>
      {special && <span className="sr-only"> (special)</span>}
    </>
  )
}
