import { dashboardColors } from '../../../utils/theme'
import { runTypeMonthlyCounts } from '../../../utils/dashboardMetrics'
import { getRunTypeDisplayName } from '../../../utils/theme'

/**
 * RunTypeSmallMultiples — a grid of tiny per-run-type monthly bar charts.
 *
 * Each panel is one run type's Jan..Dec run counts as mini bars. CRUCIAL honesty
 * detail: every panel shares the SAME y-scale (the global max across all types)
 * so panel heights are directly comparable; a tall bar means more runs full stop,
 * not just "more relative to this type". Reveals seasonality at a glance.
 *
 * Dependency-free SVG (cheaper and more controllable than a charting lib for 12
 * bars). Direct type label per panel, no legend. Responsive CSS grid that
 * collapses to fewer columns on narrow screens.
 *
 * @param {Object} data - full parseRunData output
 */

const MONTHS = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D']

function MiniBars({ monthly, globalMax, label }) {
  const W = 120
  const H = 40
  const n = monthly.length
  const gap = 2
  const barW = (W - gap * (n - 1)) / n
  const max = globalMax || 1

  return (
    <svg
      role="img"
      aria-label={`${label}: monthly run counts ${monthly.join(', ')}`}
      viewBox={`0 0 ${W} ${H}`}
      width="100%"
      height={H}
      preserveAspectRatio="none"
      style={{ display: 'block' }}
    >
      <title>{`${label} monthly runs`}</title>
      {monthly.map((v, i) => {
        const h = (v / max) * H
        const x = i * (barW + gap)
        return (
          <rect
            key={i}
            data-testid="mini-bar"
            x={x}
            y={H - h}
            width={barW}
            height={h}
            // Empty months still get a faint baseline tick so the panel reads as
            // a full Jan..Dec axis, not a truncated series.
            fill={v > 0 ? dashboardColors.ink : dashboardColors.border}
            rx={0.5}
          />
        )
      })}
    </svg>
  )
}

export default function RunTypeSmallMultiples({ data }) {
  const types = runTypeMonthlyCounts(data)
  const globalMax = types.reduce(
    (m, t) => Math.max(m, ...t.monthly),
    0
  )

  return (
    <div className="card-clean p-6">
      <div className="flex items-baseline justify-between mb-4">
        <h3 className="font-display text-lg font-semibold text-ink">Run Types Through the Year</h3>
        <span className="text-sm text-ink-muted">monthly counts, shared scale</span>
      </div>

      {types.length === 0 ? (
        <p className="text-sm text-ink-muted">No runs recorded yet this season.</p>
      ) : (
        <div
          className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-x-6 gap-y-5"
          data-testid="small-multiples-grid"
        >
          {types.map((t) => (
            <div key={t.type} data-testid="small-multiple-panel">
              <div className="flex items-baseline justify-between mb-1">
                <span className="text-xs font-medium text-ink truncate pr-2">
                  {getRunTypeDisplayName(t.type)}
                </span>
                <span className="text-xs text-ink-muted tabular-nums">{t.total}</span>
              </div>
              <MiniBars monthly={t.monthly} globalMax={globalMax} label={getRunTypeDisplayName(t.type)} />
              <div className="mt-1 flex justify-between text-[9px] text-ink-muted leading-none">
                <span>{MONTHS[0]}</span>
                <span>{MONTHS[11]}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
