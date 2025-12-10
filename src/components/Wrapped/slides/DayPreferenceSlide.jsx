import { motion } from 'framer-motion'

export default function DayPreferenceSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const dayStats = isClub ? data.dayStats : data.dayPreference

  const total = dayStats.Wed + dayStats.Fri + (dayStats.Other || 0)
  const wedPercent = total > 0 ? (dayStats.Wed / total) * 100 : 0
  const friPercent = total > 0 ? (dayStats.Fri / total) * 100 : 0

  const preference = wedPercent > friPercent + 10 ? 'wednesday' :
                     friPercent > wedPercent + 10 ? 'friday' : 'balanced'

  const messages = {
    wednesday: {
      title: isClub ? 'Midweek Warriors!' : 'Midweek Warrior!',
      subtitle: 'Wednesday runs are the favorite',
      emoji: '⚡'
    },
    friday: {
      title: isClub ? 'Weekend Welcomers!' : 'TGIF Runner!',
      subtitle: 'Friday runs hit different',
      emoji: '🎉'
    },
    balanced: {
      title: isClub ? 'Perfectly Balanced!' : 'All-Rounder!',
      subtitle: 'Every run day is a good day',
      emoji: '⚖️'
    }
  }

  const msg = messages[preference]

  return (
    <div className="min-h-screen-ios flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-indigo-900 via-purple-800 to-pink-700">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-8"
      >
        <h2 className="text-2xl text-purple-200 mb-2">Day Preference</h2>
        <p className="text-4xl md:text-5xl font-bold text-cream">
          {msg.title}
        </p>
      </motion.div>

      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", delay: 0.3 }}
        className="text-8xl mb-8"
      >
        {msg.emoji}
      </motion.div>

      <div className="w-full max-w-md space-y-4">
        {/* Wednesday bar */}
        <motion.div
          initial={{ opacity: 0, x: -50 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.5 }}
        >
          <div className="flex justify-between mb-2">
            <span className="text-cream font-medium flex items-center gap-2">
              <span className="text-2xl">📅</span> Wednesday
            </span>
            <span className="text-purple-200">{wedPercent.toFixed(0)}%</span>
          </div>
          <div className="h-8 bg-white/10 rounded-full overflow-hidden">
            <motion.div
              initial={{ width: 0 }}
              animate={{ width: `${wedPercent}%` }}
              transition={{ delay: 0.7, duration: 1 }}
              className="h-full bg-gradient-to-r from-blue-500 to-purple-500 rounded-full"
            />
          </div>
          <div className="text-right text-sm text-purple-200 mt-1">
            {dayStats.Wed} {isClub ? 'attendances' : 'runs'}
          </div>
        </motion.div>

        {/* Friday bar */}
        <motion.div
          initial={{ opacity: 0, x: -50 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.7 }}
        >
          <div className="flex justify-between mb-2">
            <span className="text-cream font-medium flex items-center gap-2">
              <span className="text-2xl">🎊</span> Friday
            </span>
            <span className="text-purple-200">{friPercent.toFixed(0)}%</span>
          </div>
          <div className="h-8 bg-white/10 rounded-full overflow-hidden">
            <motion.div
              initial={{ width: 0 }}
              animate={{ width: `${friPercent}%` }}
              transition={{ delay: 0.9, duration: 1 }}
              className="h-full bg-gradient-to-r from-pink-500 to-orange-500 rounded-full"
            />
          </div>
          <div className="text-right text-sm text-purple-200 mt-1">
            {dayStats.Fri} {isClub ? 'attendances' : 'runs'}
          </div>
        </motion.div>

        {dayStats.Other > 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 1.1 }}
            className="text-center text-purple-200 mt-4"
          >
            + {dayStats.Other} special event {isClub ? 'attendances' : 'runs'}
          </motion.div>
        )}
      </div>

      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.5 }}
        className="mt-8 text-lg text-cream/80"
      >
        {msg.subtitle}
      </motion.p>
    </div>
  )
}
