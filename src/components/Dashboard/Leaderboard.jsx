import { useState } from 'react'
import { formatNumber } from '../Poster/format'

// Places the board shows (the approved mockup).
const PLACES = 10

// The two rankings: each reads its own parser leaderboard, already sorted.
const MEASURES = {
  runs: { label: 'Runs', value: (member) => member.totalRuns },
  km: { label: 'Km', value: (member) => member.totalKm },
}

/**
 * The leaderboard panel beside On a roll: the top 10 by runs or by km, each
 * with an outlined Anton rank, a bar against the leader and the value. The
 * value is printed on every row, so the bars never need hover.
 *
 * @param {object} props
 * @param {Array<{ name: string, totalRuns: number }>} props.leaderboard -
 *   members by runs, most first (parser output)
 * @param {Array<{ name: string, totalKm: number }>} props.distanceLeaderboard -
 *   members by km, most first (parser output)
 */
export default function Leaderboard({ leaderboard, distanceLeaderboard }) {
  const [by, setBy] = useState('runs')
  const measure = MEASURES[by]
  const rows = (by === 'runs' ? leaderboard : distanceLeaderboard).slice(0, PLACES)
  const leader = rows.length ? measure.value(rows[0]) : 0

  return (
    <div>
      <div className="panel-h">
        <h3>Leaderboard</h3>
        <div className="seg" role="group" aria-label="Rank by">
          {Object.entries(MEASURES).map(([key, { label }]) => (
            <button key={key} type="button" aria-pressed={by === key} onClick={() => setBy(key)}>
              {label}
            </button>
          ))}
        </div>
      </div>

      {rows.length > 0 ? (
        <ol className="board" aria-label={`Top ${PLACES} by ${measure.label.toLowerCase()}`}>
          {rows.map((member, i) => {
            const value = measure.value(member)
            return (
              <li key={member.name} className="lb">
                <span className="r">{i + 1}</span>
                <span className="who">{member.name}</span>
                <span className="lane" aria-hidden="true">
                  <span className="bar" style={{ width: `${leader ? (value / leader) * 100 : 0}%` }} />
                </span>
                <span className="v">{formatNumber(value)}</span>
              </li>
            )
          })}
        </ol>
      ) : (
        <p className="soft">No runs yet.</p>
      )}
    </div>
  )
}
