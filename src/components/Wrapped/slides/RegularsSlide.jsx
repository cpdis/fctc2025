import { motion } from 'framer-motion'

export default function RegularsSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  if (isClub) {
    // Show the core crew - top 10 by attendance
    const coreMembers = data.leaderboard.slice(0, 10)

    return (
      <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-amber-900 via-orange-800 to-red-700">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center mb-8"
        >
          <h2 className="text-2xl text-amber-200 mb-2">The Core Crew</h2>
          <p className="text-4xl md:text-5xl font-bold text-cream">
            FCTC Regulars
          </p>
        </motion.div>

        <div className="grid grid-cols-2 gap-3 w-full max-w-md">
          {coreMembers.map((member, index) => (
            <motion.div
              key={member.name}
              initial={{ opacity: 0, scale: 0 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{
                delay: 0.3 + index * 0.08,
                type: "spring"
              }}
              className="flex items-center gap-3 p-3 rounded-xl bg-white/10"
            >
              <div className={`w-10 h-10 rounded-full flex items-center justify-center text-lg font-bold ${
                index < 3 ? 'bg-amber-400 text-amber-900' : 'bg-white/20 text-cream'
              }`}>
                {index + 1}
              </div>
              <div className="flex-1 min-w-0">
                <div className="font-medium text-cream truncate">{member.name}</div>
                <div className="text-xs text-amber-200">{member.totalRuns} runs</div>
              </div>
            </motion.div>
          ))}
        </div>

        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1.5 }}
          className="mt-8 text-center"
        >
          <p className="text-xl text-cream">
            {data.activeMembers} members ran with us in 2025!
          </p>
        </motion.div>
      </div>
    )
  }

  // Individual member - show their running buddies
  const topCoRunners = data.topCoRunners || []

  return (
    <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-amber-900 via-orange-800 to-red-700">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-8"
      >
        <h2 className="text-2xl text-amber-200 mb-2">Running Buddies</h2>
        <p className="text-4xl md:text-5xl font-bold text-cream">
          Your Top Co-Runners
        </p>
      </motion.div>

      {topCoRunners.length > 0 ? (
        <>
          <div className="space-y-3 w-full max-w-md">
            {topCoRunners.map(([name, count], index) => (
              <motion.div
                key={name}
                initial={{ opacity: 0, x: -30 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.3 + index * 0.1 }}
                className="flex items-center gap-4 p-4 rounded-2xl bg-white/10"
              >
                <div className={`w-12 h-12 rounded-full flex items-center justify-center font-bold ${
                  index === 0 ? 'bg-amber-400 text-amber-900' : 'bg-white/20 text-cream'
                }`}>
                  {index === 0 ? '🤝' : index + 1}
                </div>
                <div className="flex-1">
                  <div className="font-bold text-lg text-cream">{name}</div>
                </div>
                <div className="text-right">
                  <div className="font-bold text-2xl text-cream">{count}</div>
                  <div className="text-sm text-amber-200">runs together</div>
                </div>
              </motion.div>
            ))}
          </div>

          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 1.5 }}
            className="mt-8 text-center"
          >
            <p className="text-xl text-cream">
              You ran with {data.uniqueCoRunners} different people!
            </p>
          </motion.div>
        </>
      ) : (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.5 }}
          className="text-center text-cream/80"
        >
          <span className="text-6xl mb-4 block">👥</span>
          <p className="text-xl">More runs = more running buddies!</p>
        </motion.div>
      )}
    </div>
  )
}
