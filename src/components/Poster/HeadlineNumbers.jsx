import { formatNumber, formatSigned } from './format'

/**
 * The four headline numbers: runs, km together, runners and members per run.
 * Runs and km carry a same-date comparison with the previous season when the
 * view has one (a single season after the first); otherwise that line is left
 * out. Every value arrives computed; this only lays it out.
 *
 * @param {object} props
 * @param {number} props.runs - runs in the view
 * @param {number} props.km - member-kilometres (km x members, no +1s)
 * @param {number} props.runners - members with at least one run
 * @param {number} props.perRun - members per run, no +1s
 * @param {{ year: number, runs: number, km: number }|null} [props.delta] -
 *   this view minus the previous season at the same date, or null
 */
export default function HeadlineNumbers({ runs, km, runners, perRun, delta }) {
  const cells = [
    {
      value: formatNumber(runs),
      label: 'Runs',
      note: delta && (
        <>
          <b>{formatSigned(delta.runs)}</b> on this time in {delta.year}
        </>
      ),
    },
    {
      value: formatNumber(km),
      unit: 'km',
      label: 'Run together',
      note: delta && (
        <>
          <b>{formatSigned(delta.km)}</b> km on {delta.year}
        </>
      ),
    },
    { value: formatNumber(runners), label: 'Runners', note: 'Came to at least one run' },
    { value: formatNumber(perRun, 1), label: 'Per run', note: 'Members, not counting +1s' },
  ]

  return (
    <div className="numbers">
      {cells.map(({ value, unit, label, note }) => (
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
  )
}
