import Sparkline from './Sparkline'
import { dashboardColors } from '../../../utils/theme'
import { memberMonthlyAttendance } from '../../../utils/dashboardMetrics'

const MONTHS = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D']

/**
 * SparklineLeaderboard — the high-density centerpiece.
 *
 * One row per active member: name, total runs, total km, a 12-month attendance
 * sparkline (Jan..Dec, aligned because the metric guarantees fixed length), and
 * the current attendance streak. Hairline row separators, numerals in ink,
 * labels muted. This is Tufte's "data table as graphic": every member's whole
 * season legible at a glance, vertically scannable.
 *
 * Mobile: the table sits in a horizontal-scroll container so the sparkline and
 * streak columns never collapse; name + totals stay readable as you scroll.
 *
 * @param {Object} data - full parseRunData output
 */
export default function SparklineLeaderboard({ data }) {
  const rows = memberMonthlyAttendance(data)

  return (
    <div className="card-clean p-6">
      <div className="flex items-baseline justify-between mb-4">
        <h3 className="font-display text-lg font-semibold text-ink">Member Season</h3>
        <span className="text-sm text-ink-muted">{rows.length} active</span>
      </div>

      {rows.length === 0 ? (
        <p className="text-sm text-ink-muted">No member attendance yet this season.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[560px] border-collapse" data-testid="sparkline-leaderboard">
            <thead>
              <tr className="text-left text-xs uppercase tracking-wide text-ink-muted">
                <th className="py-2 pr-3 font-medium">Member</th>
                <th className="py-2 px-3 font-medium text-right">Runs</th>
                <th className="py-2 px-3 font-medium text-right">Km</th>
                <th className="py-2 px-3 font-medium w-full">Jan–Dec</th>
                <th className="py-2 pl-3 font-medium text-right">Streak</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((m) => (
                <tr
                  key={m.name}
                  data-testid="leaderboard-row"
                  className="border-t border-border"
                >
                  <td className="py-2.5 pr-3 text-ink font-medium whitespace-nowrap">
                    {m.name}
                  </td>
                  <td className="py-2.5 px-3 text-right text-ink tabular-nums">
                    {m.totalRuns}
                  </td>
                  <td className="py-2.5 px-3 text-right text-ink tabular-nums">
                    {Math.round(m.totalKm).toLocaleString()}
                  </td>
                  <td className="py-2.5 px-3 w-full">
                    <Sparkline
                      data={m.monthly}
                      width={240}
                      height={28}
                      color={dashboardColors.ink}
                      strokeWidth={1.25}
                      ariaLabel={`${m.name} monthly attendance, ${m.monthly.join(', ')} from January to December`}
                    />
                  </td>
                  <td className="py-2.5 pl-3 text-right tabular-nums">
                    {m.currentStreak > 0 ? (
                      <span className="text-ink font-semibold">{m.currentStreak}</span>
                    ) : (
                      <span className="text-ink-muted">0</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Quiet caption clarifying the sparkline x-axis, in lieu of inline axis. */}
      <p className="mt-3 text-xs text-ink-muted">
        Sparklines span <span className="font-medium text-ink">{MONTHS.join(' ')}</span>{' '}
        (January to December). Streak = consecutive most-recent runs attended.
      </p>
    </div>
  )
}
