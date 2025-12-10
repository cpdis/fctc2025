import { motion } from 'framer-motion'
import { runTypeColors } from '../../../utils/theme'

const runTypeEmojis = {
  'Intervals': '⚡',
  'Social': '🍻',
  'Soft Sand': '🏖️',
  'Lakes Loop': '💧',
  'River Loop': '🌊',
  "N'hood Loop": '🏘️',
  'Hills': '⛰️',
  'Half Marathon': '🏃',
  'Marathon': '🎖️',
  '10K': '🔟',
  'Filament Cup': '🏆',
}

const runTypeQuotes = {
  'Intervals': "Speed is your game!",
  'Social': "Running is better with friends!",
  'Soft Sand': "Beach beast mode activated!",
  'Lakes Loop': "Scenic route enthusiast!",
  'River Loop': "River runner extraordinaire!",
  "N'hood Loop": "Local legend!",
  'Hills': "What goes up must come down!",
}

// Running shoe animation
const RunningShoe = () => (
  <motion.div
    className="absolute"
    initial={{ x: -100, y: 50, opacity: 0 }}
    animate={{
      x: [null, 0, 100],
      y: [50, 0, 50],
      opacity: [0, 1, 0],
      rotate: [0, -10, 0],
    }}
    transition={{
      duration: 2,
      delay: 0.5,
      times: [0, 0.5, 1],
    }}
  >
    <span className="text-6xl">👟</span>
  </motion.div>
)

export default function FavoriteRunSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  if (isClub) {
    const topTypes = Object.entries(clubData.runsByType)
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 5)

    return (
      <div className="min-h-screen flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-purple-900 via-indigo-800 to-blue-700 relative overflow-hidden">
        {/* Background glow */}
        <motion.div
          className="absolute w-96 h-96 rounded-full opacity-20"
          style={{ background: 'radial-gradient(circle, #8b5cf6 0%, transparent 70%)' }}
          animate={{
            scale: [1, 1.2, 1],
            opacity: [0.15, 0.25, 0.15],
          }}
          transition={{ duration: 5, repeat: Infinity, ease: "easeInOut" }}
        />

        <motion.div
          initial={{ opacity: 0, y: -30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: "spring" }}
          className="text-center mb-8 relative z-10"
        >
          <motion.h2
            className="font-display text-2xl text-purple-200 mb-2"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.2 }}
          >
            The Favorites
          </motion.h2>
          <motion.p
            className="font-display text-4xl md:text-5xl font-bold text-cream"
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ delay: 0.3, type: "spring" }}
          >
            Most Popular Runs
          </motion.p>
        </motion.div>

        <div className="space-y-4 w-full max-w-md relative z-10">
          {topTypes.map(([type, typeStats], index) => (
            <motion.div
              key={type}
              initial={{ opacity: 0, x: 50, rotate: 2 }}
              animate={{ opacity: 1, x: 0, rotate: 0 }}
              transition={{
                delay: 0.4 + index * 0.12,
                type: "spring",
                stiffness: 200,
                damping: 15
              }}
              whileHover={{ scale: 1.02, x: -5 }}
              className="flex items-center gap-4 p-4 rounded-2xl bg-white/10 backdrop-blur-sm border border-white/10"
            >
              <motion.div
                className="w-14 h-14 rounded-xl flex items-center justify-center text-3xl"
                style={{
                  backgroundColor: runTypeColors[type] || '#6F4E37',
                  boxShadow: `0 4px 20px ${runTypeColors[type]}40`
                }}
                whileHover={{ scale: 1.1, rotate: [0, -5, 5, 0] }}
              >
                {runTypeEmojis[type] || '🏃'}
              </motion.div>
              <div className="flex-1">
                <div className="font-display font-bold text-lg text-cream">{type}</div>
                <div className="text-sm text-purple-200">{typeStats.count} runs</div>
              </div>
              <motion.div
                className="text-right text-cream/80"
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                transition={{ delay: 0.6 + index * 0.1, type: "spring" }}
              >
                <div className="font-display font-bold">{typeStats.totalKm.toFixed(0)} km</div>
              </motion.div>
            </motion.div>
          ))}
        </div>
      </div>
    )
  }

  // Individual member view
  const favorite = data.favoriteRunType

  if (!favorite) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-purple-900 to-blue-700">
        <p className="text-cream text-xl">Not enough data yet!</p>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-purple-900 via-indigo-800 to-blue-700 relative overflow-hidden">
      {/* Running shoe animation */}
      <RunningShoe />

      {/* Background glow matching the run type color */}
      <motion.div
        className="absolute w-80 h-80 rounded-full opacity-30"
        style={{ background: `radial-gradient(circle, ${runTypeColors[favorite.type] || '#6F4E37'} 0%, transparent 70%)` }}
        animate={{
          scale: [1, 1.3, 1],
          opacity: [0.2, 0.4, 0.2],
        }}
        transition={{ duration: 3, repeat: Infinity, ease: "easeInOut" }}
      />

      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-4 relative z-10"
      >
        <h2 className="font-display text-2xl text-purple-200">Your Favorite Run</h2>
      </motion.div>

      <motion.div
        initial={{ scale: 0, rotate: -30 }}
        animate={{ scale: 1, rotate: 0 }}
        transition={{ type: "spring", stiffness: 200, damping: 15, delay: 0.3 }}
        whileHover={{ scale: 1.05, rotate: [0, -5, 5, 0] }}
        className="w-40 h-40 mb-6 rounded-3xl flex items-center justify-center relative z-10"
        style={{
          backgroundColor: runTypeColors[favorite.type] || '#6F4E37',
          boxShadow: `0 12px 40px ${runTypeColors[favorite.type]}60, 0 6px 20px ${runTypeColors[favorite.type]}40`
        }}
      >
        <motion.span
          className="text-8xl"
          animate={{
            y: [0, -5, 0],
            rotate: [0, 5, -5, 0],
          }}
          transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
        >
          {runTypeEmojis[favorite.type] || '🏃'}
        </motion.span>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.6, type: "spring" }}
        className="text-center relative z-10"
      >
        <motion.p
          className="font-display text-5xl md:text-6xl font-bold text-cream mb-4"
          initial={{ scaleY: 0.5, scaleX: 1.2 }}
          animate={{ scaleY: 1, scaleX: 1 }}
          transition={{ delay: 0.7, type: "spring", stiffness: 300 }}
        >
          {favorite.type}
        </motion.p>
        <p className="text-2xl text-purple-200 font-medium">
          {favorite.count} times this year
        </p>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, scale: 0.8 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ delay: 1, type: "spring" }}
        className="mt-8 px-6 py-3 bg-white/15 backdrop-blur-sm rounded-full border border-white/20 relative z-10"
      >
        <span className="text-lg text-cream font-medium">
          {runTypeQuotes[favorite.type] || "Keep running!"}
        </span>
      </motion.div>
    </div>
  )
}
