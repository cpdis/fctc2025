import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

export default function Leaderboard({ leaderboard, distanceLeaderboard }) {
  const [view, setView] = useState('attendance') // 'attendance' or 'distance'

  const currentLeaderboard = view === 'attendance' ? leaderboard : distanceLeaderboard
  const displayList = currentLeaderboard.slice(0, 10)

  const maxValue = view === 'attendance'
    ? displayList[0]?.totalRuns || 1
    : displayList[0]?.totalKm || 1

  return (
    <div className="bg-white rounded-2xl shadow-md p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-bold text-espresso">Leaderboard</h3>

        <div className="flex rounded-lg bg-cream-dark p-1">
          <button
            onClick={() => setView('attendance')}
            className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
              view === 'attendance'
                ? 'bg-coffee text-cream'
                : 'text-coffee hover:bg-latte/50'
            }`}
          >
            Runs
          </button>
          <button
            onClick={() => setView('distance')}
            className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
              view === 'distance'
                ? 'bg-coffee text-cream'
                : 'text-coffee hover:bg-latte/50'
            }`}
          >
            Distance
          </button>
        </div>
      </div>

      <div className="space-y-2">
        <AnimatePresence mode="wait">
          {displayList.map((member, index) => {
            const value = view === 'attendance' ? member.totalRuns : member.totalKm
            const percentage = (value / maxValue) * 100

            return (
              <motion.div
                key={`${view}-${member.name}`}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: 20 }}
                transition={{ delay: index * 0.03 }}
                className="relative"
              >
                <div className="flex items-center gap-3 py-2 px-3 rounded-lg hover:bg-cream-dark transition-colors">
                  {/* Rank */}
                  <div className={`w-7 h-7 rounded-full flex items-center justify-center text-sm font-bold ${
                    index === 0 ? 'bg-yellow-400 text-yellow-900' :
                    index === 1 ? 'bg-gray-300 text-gray-700' :
                    index === 2 ? 'bg-amber-600 text-white' :
                    'bg-latte text-coffee'
                  }`}>
                    {index + 1}
                  </div>

                  {/* Name */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-1">
                      <span className="font-medium text-espresso truncate">{member.name}</span>
                      <span className="text-sm font-bold text-coffee ml-2">
                        {view === 'attendance'
                          ? member.totalRuns
                          : `${member.totalKm.toFixed(1)} km`
                        }
                      </span>
                    </div>

                    {/* Progress bar */}
                    <div className="h-1.5 bg-cream-dark rounded-full overflow-hidden">
                      <motion.div
                        initial={{ width: 0 }}
                        animate={{ width: `${percentage}%` }}
                        transition={{ duration: 0.5, delay: index * 0.03 }}
                        className={`h-full rounded-full ${
                          index === 0 ? 'bg-terracotta' :
                          index < 3 ? 'bg-coffee' :
                          'bg-latte'
                        }`}
                      />
                    </div>
                  </div>
                </div>
              </motion.div>
            )
          })}
        </AnimatePresence>
      </div>

      <div className="mt-4 pt-4 border-t border-cream-dark text-center text-sm text-coffee/70">
        {view === 'attendance' ? 'Ranked by number of runs attended' : 'Ranked by total kilometers'}
      </div>
    </div>
  )
}
