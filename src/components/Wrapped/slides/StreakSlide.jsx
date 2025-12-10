import { motion } from 'framer-motion'

export default function StreakSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  if (isClub) {
    // For club, show the most consistent members
    const consistentMembers = clubData.leaderboard
      .filter(m => m.totalRuns >= clubData.totalRuns * 0.5)
      .slice(0, 5)

    return (
      <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-orange-900 via-red-800 to-pink-700">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center mb-8"
        >
          <h2 className="text-2xl text-orange-200 mb-2">Consistency Kings</h2>
          <p className="text-4xl md:text-5xl font-bold text-cream">
            50%+ Attendance Club
          </p>
        </motion.div>

        {consistentMembers.length > 0 ? (
          <div className="space-y-3 w-full max-w-md">
            {consistentMembers.map((member, index) => (
              <motion.div
                key={member.name}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: 0.3 + index * 0.1 }}
                className="flex items-center gap-4 p-4 rounded-2xl bg-white/10"
              >
                <div className="text-3xl">🔥</div>
                <div className="flex-1">
                  <div className="font-bold text-lg text-cream">{member.name}</div>
                </div>
                <div className="text-right">
                  <div className="font-bold text-xl text-cream">
                    {((member.totalRuns / clubData.totalRuns) * 100).toFixed(0)}%
                  </div>
                  <div className="text-sm text-orange-200">attendance</div>
                </div>
              </motion.div>
            ))}
          </div>
        ) : (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.5 }}
            className="text-center text-cream/80"
          >
            <p className="text-xl">Keep pushing - the 50% club awaits!</p>
          </motion.div>
        )}
      </div>
    )
  }

  // Individual member view
  const maxStreak = data.maxStreak || 0
  const currentStreak = data.currentStreak || 0

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-orange-900 via-red-800 to-pink-700">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-6"
      >
        <h2 className="text-2xl text-orange-200">Streak Status</h2>
      </motion.div>

      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", delay: 0.3 }}
        className="flex items-center justify-center gap-2 mb-8"
      >
        {[...Array(Math.min(maxStreak, 10))].map((_, i) => (
          <motion.span
            key={i}
            initial={{ scale: 0, rotate: -180 }}
            animate={{ scale: 1, rotate: 0 }}
            transition={{ delay: 0.5 + i * 0.1 }}
            className="text-4xl md:text-5xl"
          >
            🔥
          </motion.span>
        ))}
        {maxStreak > 10 && (
          <span className="text-2xl text-cream font-bold">+{maxStreak - 10}</span>
        )}
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 1 }}
        className="text-center space-y-6"
      >
        <div>
          <p className="text-5xl md:text-7xl font-bold text-cream mb-2">{maxStreak}</p>
          <p className="text-xl text-orange-200">run streak (best)</p>
        </div>

        {currentStreak > 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 1.5 }}
            className="px-6 py-3 bg-white/10 rounded-full"
          >
            <span className="text-lg text-cream">
              Currently on a {currentStreak} run streak! 🔥
            </span>
          </motion.div>
        )}

        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 2 }}
          className="text-lg text-cream/80"
        >
          {maxStreak >= 10 ? "Incredible dedication!" :
           maxStreak >= 5 ? "Solid consistency!" :
           "Every run counts!"}
        </motion.p>
      </motion.div>
    </div>
  )
}
