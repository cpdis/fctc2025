import { motion } from 'framer-motion'

// Animated fire component with flickering effect
const AnimatedFire = ({ size = 'md', delay = 0 }) => {
  const sizes = {
    sm: 'text-3xl',
    md: 'text-4xl md:text-5xl',
    lg: 'text-5xl md:text-6xl'
  }

  return (
    <motion.div
      className="relative"
      initial={{ scale: 0, rotate: -180 }}
      animate={{ scale: 1, rotate: 0 }}
      transition={{ delay, type: "spring", stiffness: 300 }}
    >
      <motion.span
        className={sizes[size]}
        animate={{
          y: [0, -3, 0],
          scale: [1, 1.1, 1],
          rotate: [-3, 3, -3],
        }}
        transition={{
          duration: 0.5,
          repeat: Infinity,
          ease: "easeInOut"
        }}
      >
        🔥
      </motion.span>
      {/* Glow effect */}
      <motion.div
        className="absolute inset-0 rounded-full blur-lg opacity-50"
        style={{ background: 'radial-gradient(circle, #ff6b00 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.3, 1],
          opacity: [0.3, 0.6, 0.3],
        }}
        transition={{ duration: 0.8, repeat: Infinity }}
      />
    </motion.div>
  )
}

// Ember particle
const Ember = ({ delay }) => (
  <motion.div
    className="absolute w-1.5 h-1.5 rounded-full bg-orange-400"
    style={{
      left: `${30 + Math.random() * 40}%`,
      bottom: '60%',
    }}
    initial={{ opacity: 0, y: 0, scale: 0 }}
    animate={{
      opacity: [0, 1, 0],
      y: [-10, -60],
      scale: [0, 1, 0],
      x: [(Math.random() - 0.5) * 30, (Math.random() - 0.5) * 50],
    }}
    transition={{
      duration: 1.5,
      delay,
      repeat: Infinity,
      ease: "easeOut"
    }}
  />
)

export default function StreakSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  if (isClub) {
    // For club, show the most consistent members
    const consistentMembers = clubData.leaderboard
      .filter(m => m.totalRuns >= clubData.totalRuns * 0.5)
      .slice(0, 5)

    return (
      <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-orange-900 via-red-800 to-pink-700 relative overflow-hidden">
        {/* Background flames */}
        <motion.div
          className="absolute bottom-0 left-0 right-0 h-40 opacity-20"
          style={{
            background: 'linear-gradient(to top, #ff6b00, transparent)'
          }}
          animate={{
            opacity: [0.15, 0.25, 0.15],
          }}
          transition={{ duration: 2, repeat: Infinity }}
        />

        <motion.div
          initial={{ opacity: 0, y: -30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: "spring" }}
          className="text-center mb-8 relative z-10"
        >
          <motion.h2
            className="font-display text-2xl text-orange-200 mb-2"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.2 }}
          >
            Consistency Kings
          </motion.h2>
          <motion.p
            className="font-display text-4xl md:text-5xl font-bold text-cream"
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ delay: 0.3, type: "spring" }}
          >
            50%+ Attendance Club
          </motion.p>
        </motion.div>

        {consistentMembers.length > 0 ? (
          <div className="space-y-3 w-full max-w-md relative z-10">
            {consistentMembers.map((member, index) => (
              <motion.div
                key={member.name}
                initial={{ opacity: 0, x: -40, scale: 0.9 }}
                animate={{ opacity: 1, x: 0, scale: 1 }}
                transition={{
                  delay: 0.4 + index * 0.1,
                  type: "spring",
                  stiffness: 200
                }}
                whileHover={{ scale: 1.02, x: 5 }}
                className="flex items-center gap-4 p-4 rounded-2xl bg-white/10 backdrop-blur-sm border border-white/10"
              >
                <AnimatedFire size="sm" delay={0.5 + index * 0.1} />
                <div className="flex-1">
                  <div className="font-display font-bold text-lg text-cream">{member.name}</div>
                </div>
                <div className="text-right">
                  <motion.div
                    className="font-display font-bold text-xl text-cream"
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={{ delay: 0.6 + index * 0.1, type: "spring" }}
                  >
                    {((member.totalRuns / clubData.totalRuns) * 100).toFixed(0)}%
                  </motion.div>
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
            className="text-center text-cream/80 relative z-10"
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
    <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-orange-900 via-red-800 to-pink-700 relative overflow-hidden">
      {/* Ember particles */}
      {[...Array(8)].map((_, i) => (
        <Ember key={i} delay={i * 0.3} />
      ))}

      {/* Background glow */}
      <motion.div
        className="absolute w-96 h-96 rounded-full opacity-30"
        style={{ background: 'radial-gradient(circle, #ff6b00 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.3, 1],
          opacity: [0.2, 0.4, 0.2],
        }}
        transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
      />

      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-6 relative z-10"
      >
        <h2 className="font-display text-2xl text-orange-200">Streak Status</h2>
      </motion.div>

      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", delay: 0.3 }}
        className="flex items-center justify-center gap-1 mb-8 relative z-10"
      >
        {[...Array(Math.min(maxStreak, 10))].map((_, i) => (
          <AnimatedFire key={i} size="md" delay={0.4 + i * 0.08} />
        ))}
        {maxStreak > 10 && (
          <motion.span
            className="font-display text-2xl text-cream font-bold ml-2"
            initial={{ opacity: 0, scale: 0 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 1.2, type: "spring" }}
          >
            +{maxStreak - 10}
          </motion.span>
        )}
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 1 }}
        className="text-center space-y-6 relative z-10"
      >
        <div>
          <motion.p
            className="font-display text-5xl md:text-7xl font-bold text-cream mb-2"
            initial={{ scaleY: 0.5, scaleX: 1.2 }}
            animate={{ scaleY: 1, scaleX: 1 }}
            transition={{ delay: 1.1, type: "spring", stiffness: 300 }}
          >
            {maxStreak}
          </motion.p>
          <p className="text-xl text-orange-200 font-medium">run streak (best)</p>
        </div>

        {currentStreak > 0 && (
          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 1.5, type: "spring" }}
            className="px-6 py-3 bg-white/15 backdrop-blur-sm rounded-full border border-white/20 inline-flex items-center gap-2"
          >
            <AnimatedFire size="sm" delay={1.6} />
            <span className="text-lg text-cream font-medium">
              Currently on a {currentStreak} run streak!
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
