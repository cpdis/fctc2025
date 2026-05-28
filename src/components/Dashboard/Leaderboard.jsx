import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { dataColors, dashboardColors } from '../../utils/theme'

// Neutral rank chip. The top spot gets the ink accent, everyone else a quiet
// grey chip. No medals, no gradients, no springs (Tufte: rank is the data, the
// chip is just a label).
const RankBadge = ({ rank }) => {
  const isTop = rank === 1
  return (
    <div
      className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-semibold tabular-nums flex-shrink-0 ${
        isTop ? 'bg-accent text-card' : 'bg-surface text-ink-muted border border-border'
      }`}
    >
      {rank}
    </div>
  )
}

// Bar colors: #1 in ink (primary data-ink), #2 in the burnt-orange accent,
// everyone else recedes into greys. Mirrors the restrained data palette.
const barColor = (index) => {
  if (index === 0) return dataColors[0]
  if (index === 1) return dataColors[1]
  return dataColors[3]
}

export default function Leaderboard({ leaderboard, distanceLeaderboard }) {
  const [view, setView] = useState('attendance')

  const currentLeaderboard = view === 'attendance' ? leaderboard : distanceLeaderboard
  const displayList = currentLeaderboard.slice(0, 10)

  const maxValue = view === 'attendance'
    ? displayList[0]?.totalRuns || 1
    : displayList[0]?.totalKm || 1

  const tabClass = (active) =>
    `px-3 py-1 rounded-full text-sm font-medium transition-colors ${
      active ? 'bg-accent text-card' : 'text-ink-muted hover:text-ink'
    }`

  return (
    <div className="card-clean p-6 h-full">
      <div className="flex items-center justify-between mb-5">
        <h3 className="font-display text-lg font-semibold text-ink">Leaderboard</h3>

        <div className="flex items-center rounded-full border border-border p-0.5">
          <button onClick={() => setView('attendance')} className={tabClass(view === 'attendance')}>
            Runs
          </button>
          <button onClick={() => setView('distance')} className={tabClass(view === 'distance')}>
            Distance
          </button>
        </div>
      </div>

      <div className="space-y-1">
        <AnimatePresence mode="wait">
          {displayList.map((member, index) => {
            const value = view === 'attendance' ? member.totalRuns : member.totalKm
            const percentage = (value / maxValue) * 100

            return (
              <motion.div
                key={`${view}-${member.name}`}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2, delay: index * 0.02 }}
                className="flex items-center gap-3 py-2 px-2 rounded-lg hover:bg-surface transition-colors"
              >
                <RankBadge rank={index + 1} />

                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-sm text-ink truncate">{member.name}</span>
                    <span className="text-sm font-semibold text-ink ml-2 tabular-nums">
                      {view === 'attendance' ? member.totalRuns : `${member.totalKm.toFixed(0)} km`}
                    </span>
                  </div>

                  <div className="h-1.5 rounded-full overflow-hidden" style={{ background: dashboardColors.border }}>
                    <motion.div
                      initial={{ width: 0 }}
                      animate={{ width: `${percentage}%` }}
                      transition={{ duration: 0.5, delay: index * 0.03, ease: 'easeOut' }}
                      className="h-full rounded-full"
                      style={{ background: barColor(index) }}
                    />
                  </div>
                </div>
              </motion.div>
            )
          })}
        </AnimatePresence>
      </div>

      <div className="mt-5 pt-4 border-t border-border text-center text-sm text-ink-muted">
        {view === 'attendance' ? 'Ranked by number of runs attended' : 'Ranked by total kilometers'}
      </div>
    </div>
  )
}
