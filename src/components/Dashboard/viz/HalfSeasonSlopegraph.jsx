import Slopegraph from './Slopegraph'
import { firstVsSecondHalf } from '../../../utils/dashboardMetrics'

// A 30-row slopegraph is unreadable. Cap to the most active members; the rest are
// noted below the chart so nothing is silently dropped.
const MAX_ROWS = 12

/**
 * HalfSeasonSlopegraph — "who's showing up more / less" across the season halves.
 *
 * Splits each member's attendance at the TRUE data midpoint (the metric handles
 * this, honest for partial seasons) and draws a slope from first-half to
 * second-half attendance. Rising slopes (accent) = ramping up; falling slopes
 * (grey) = tailing off. Capped to the top members by total attendance.
 *
 * @param {Object} data - full parseRunData output
 */
export default function HalfSeasonSlopegraph({ data }) {
  const all = firstVsSecondHalf(data)
  // Metric already sorts by total (first + second) desc, so the head is the most
  // active members.
  const shown = all.slice(0, MAX_ROWS)
  const hidden = all.length - shown.length

  const slopeData = shown.map((m) => ({
    label: m.name,
    left: m.first,
    right: m.second,
  }))

  // Height scales with row count so labels never collide; keep a sane minimum.
  const height = Math.max(180, shown.length * 22 + 56)

  return (
    <div className="card-clean p-6">
      <div className="flex items-baseline justify-between mb-4">
        <h3 className="font-display text-lg font-semibold text-ink">Showing Up More or Less</h3>
        <span className="text-sm text-ink-muted">attendance, split at season midpoint</span>
      </div>

      {slopeData.length === 0 ? (
        <p className="text-sm text-ink-muted">Not enough runs to split the season yet.</p>
      ) : (
        <>
          {/* Horizontal scroll keeps the two-column layout legible on phones. */}
          <div className="overflow-x-auto">
            <div className="min-w-[360px]">
              <Slopegraph
                data={slopeData}
                width={360}
                height={height}
                leftTitle="First half"
                rightTitle="Second half"
                ariaLabel="First-half versus second-half attendance per member"
              />
            </div>
          </div>
          {hidden > 0 && (
            <p className="mt-3 text-xs text-ink-muted">
              Showing the {MAX_ROWS} most active members. {hidden} more not shown.
            </p>
          )}
        </>
      )}
    </div>
  )
}
