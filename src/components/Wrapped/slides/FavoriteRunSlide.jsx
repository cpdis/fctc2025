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

export default function FavoriteRunSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  if (isClub) {
    const topTypes = Object.entries(clubData.runsByType)
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 5)

    return (
      <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-purple-900 via-indigo-800 to-blue-700">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center mb-8"
        >
          <h2 className="text-2xl text-purple-200 mb-2">The Favorites</h2>
          <p className="text-4xl md:text-5xl font-bold text-cream">
            Most Popular Runs
          </p>
        </motion.div>

        <div className="space-y-4 w-full max-w-md">
          {topTypes.map(([type, stats], index) => (
            <motion.div
              key={type}
              initial={{ opacity: 0, x: 50 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.3 + index * 0.15 }}
              className="flex items-center gap-4 p-4 rounded-2xl bg-white/10"
            >
              <div className="w-14 h-14 rounded-xl flex items-center justify-center text-3xl"
                style={{ backgroundColor: runTypeColors[type] || '#6F4E37' }}
              >
                {runTypeEmojis[type] || '🏃'}
              </div>
              <div className="flex-1">
                <div className="font-bold text-lg text-cream">{type}</div>
                <div className="text-sm text-purple-200">{stats.count} runs</div>
              </div>
              <div className="text-right text-cream/80">
                <div className="font-bold">{stats.totalKm.toFixed(0)} km</div>
              </div>
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
      <div className="min-h-screen flex items-center justify-center p-8 bg-gradient-to-br from-purple-900 to-blue-700">
        <p className="text-cream text-xl">Not enough data yet!</p>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-purple-900 via-indigo-800 to-blue-700">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-4"
      >
        <h2 className="text-2xl text-purple-200">Your Favorite Run</h2>
      </motion.div>

      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", delay: 0.3 }}
        className="w-40 h-40 mb-6 rounded-3xl flex items-center justify-center shadow-2xl"
        style={{ backgroundColor: runTypeColors[favorite.type] || '#6F4E37' }}
      >
        <span className="text-8xl">{runTypeEmojis[favorite.type] || '🏃'}</span>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.6 }}
        className="text-center"
      >
        <p className="text-5xl md:text-6xl font-bold text-cream mb-4">
          {favorite.type}
        </p>
        <p className="text-2xl text-purple-200">
          {favorite.count} times this year
        </p>
      </motion.div>

      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1 }}
        className="mt-8 px-6 py-3 bg-white/10 rounded-full"
      >
        <span className="text-lg text-cream">
          {runTypeQuotes[favorite.type] || "Keep running!"}
        </span>
      </motion.div>
    </div>
  )
}
