import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

// Playful rank badge component
const RankBadge = ({ rank }) => {
  if (rank === 1) {
    return (
      <motion.div
        className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold relative"
        style={{
          background: 'linear-gradient(135deg, #fbbf24 0%, #f59e0b 100%)',
          boxShadow: '0 2px 8px rgba(245, 158, 11, 0.4)'
        }}
        whileHover={{ scale: 1.1, rotate: [0, -5, 5, 0] }}
      >
        <span className="text-yellow-900">1</span>
        {/* Crown icon */}
        <motion.span
          className="absolute -top-2 text-yellow-500"
          initial={{ y: 5, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.3 }}
        >
          <svg className="w-4 h-4" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 1L9 9L1 8L7 14L5 22L12 18L19 22L17 14L23 8L15 9L12 1Z" />
          </svg>
        </motion.span>
      </motion.div>
    )
  }

  if (rank === 2) {
    return (
      <motion.div
        className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold"
        style={{
          background: 'linear-gradient(135deg, #e5e7eb 0%, #9ca3af 100%)',
          boxShadow: '0 2px 8px rgba(156, 163, 175, 0.4)'
        }}
        whileHover={{ scale: 1.1 }}
      >
        <span className="text-gray-700">2</span>
      </motion.div>
    )
  }

  if (rank === 3) {
    return (
      <motion.div
        className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold"
        style={{
          background: 'linear-gradient(135deg, #d97706 0%, #b45309 100%)',
          boxShadow: '0 2px 8px rgba(180, 83, 9, 0.3)'
        }}
        whileHover={{ scale: 1.1 }}
      >
        <span className="text-white">3</span>
      </motion.div>
    )
  }

  return (
    <div className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold bg-cream-dark text-coffee/70">
      {rank}
    </div>
  )
}

export default function Leaderboard({ leaderboard, distanceLeaderboard }) {
  const [view, setView] = useState('attendance')

  const currentLeaderboard = view === 'attendance' ? leaderboard : distanceLeaderboard
  const displayList = currentLeaderboard.slice(0, 10)

  const maxValue = view === 'attendance'
    ? displayList[0]?.totalRuns || 1
    : displayList[0]?.totalKm || 1

  return (
    <div
      className="bg-white rounded-2xl p-6 relative overflow-hidden"
      style={{
        boxShadow: `
          0 1px 2px rgba(2, 9, 18, 0.04),
          0 4px 12px rgba(2, 9, 18, 0.06)
        `
      }}
    >
      {/* Subtle accent line */}
      <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-terracotta via-pink to-mint opacity-60" />

      <div className="flex items-center justify-between mb-5">
        <h3 className="font-display text-lg font-bold text-espresso">Leaderboard</h3>

        <div className="flex rounded-xl bg-cream p-1 gap-1">
          <motion.button
            onClick={() => setView('attendance')}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors relative ${
              view === 'attendance'
                ? 'text-cream'
                : 'text-coffee hover:text-espresso'
            }`}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
          >
            {view === 'attendance' && (
              <motion.div
                layoutId="leaderboardTab"
                className="absolute inset-0 bg-gradient-to-r from-coffee to-pink-dark rounded-lg"
                transition={{ type: "spring", stiffness: 400, damping: 30 }}
              />
            )}
            <span className="relative z-10">Runs</span>
          </motion.button>
          <motion.button
            onClick={() => setView('distance')}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors relative ${
              view === 'distance'
                ? 'text-cream'
                : 'text-coffee hover:text-espresso'
            }`}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
          >
            {view === 'distance' && (
              <motion.div
                layoutId="leaderboardTab"
                className="absolute inset-0 bg-gradient-to-r from-coffee to-pink-dark rounded-lg"
                transition={{ type: "spring", stiffness: 400, damping: 30 }}
              />
            )}
            <span className="relative z-10">Distance</span>
          </motion.button>
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
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: 20 }}
                transition={{ delay: index * 0.03, type: "spring", stiffness: 300 }}
                className="relative group"
              >
                <div className="flex items-center gap-3 py-2.5 px-3 rounded-xl hover:bg-cream/50 transition-all duration-200">
                  <RankBadge rank={index + 1} />

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-1.5">
                      <span className="font-medium text-espresso truncate">{member.name}</span>
                      <span className="font-display text-sm font-bold text-coffee ml-2 tabular-nums">
                        {view === 'attendance'
                          ? member.totalRuns
                          : `${member.totalKm.toFixed(0)} km`
                        }
                      </span>
                    </div>

                    {/* Organic progress bar */}
                    <div className="h-2 bg-cream rounded-full overflow-hidden">
                      <motion.div
                        initial={{ width: 0, opacity: 0 }}
                        animate={{ width: `${percentage}%`, opacity: 1 }}
                        transition={{
                          duration: 0.6,
                          delay: index * 0.05,
                          ease: [0.34, 1.56, 0.64, 1]
                        }}
                        className={`h-full rounded-full ${
                          index === 0 ? 'bg-gradient-to-r from-terracotta to-orange' :
                          index === 1 ? 'bg-gradient-to-r from-pink to-coffee' :
                          index === 2 ? 'bg-gradient-to-r from-amber to-amber-dark' :
                          'bg-gradient-to-r from-mint/70 to-mint-dark/50'
                        }`}
                        style={{
                          borderRadius: '9999px 12px 8px 9999px' // Slightly organic ends
                        }}
                      />
                    </div>
                  </div>
                </div>
              </motion.div>
            )
          })}
        </AnimatePresence>
      </div>

      <div className="mt-5 pt-4 border-t border-cream text-center text-sm text-coffee/60 font-medium">
        {view === 'attendance' ? 'Ranked by number of runs attended' : 'Ranked by total kilometers'}
      </div>
    </div>
  )
}
