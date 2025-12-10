import { motion } from 'framer-motion'

const monthEmojis = {
  'Jan': '🎆', 'Feb': '💕', 'Mar': '🍀', 'Apr': '🌸',
  'May': '🌺', 'Jun': '❄️', 'Jul': '🧣', 'Aug': '🌬️',
  'Sep': '🌼', 'Oct': '🎃', 'Nov': '🦃', 'Dec': '🎄'
}

export default function PeakMonthSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const peakMonth = data.peakMonth
  // Use member's own monthly data for individual members, club data for club view
  const monthlyData = isClub ? clubData.runsByMonth : data.monthlyData

  if (!peakMonth) {
    return (
      <div className="min-h-screen flex items-center justify-center p-8 bg-gradient-to-br from-cyan-900 to-blue-700">
        <p className="text-cream text-xl">Not enough monthly data yet!</p>
      </div>
    )
  }

  // Sort months chronologically
  const monthOrder = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
  const sortedMonths = monthOrder
    .filter(m => monthlyData[m])
    .map(m => ({
      month: m,
      ...monthlyData[m]
    }))

  const maxAttendance = Math.max(...sortedMonths.map(m => m.totalAttendance))

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-cyan-900 via-teal-800 to-emerald-700">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-6"
      >
        <h2 className="text-2xl text-cyan-200 mb-2">Peak Performance</h2>
        <p className="text-4xl md:text-5xl font-bold text-cream">
          {isClub ? 'Busiest Month' : 'Your Peak Month'}
        </p>
      </motion.div>

      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", delay: 0.3 }}
        className="text-center mb-8"
      >
        <span className="text-8xl">{monthEmojis[peakMonth.month] || '📅'}</span>
        <p className="text-5xl md:text-6xl font-bold text-cream mt-4">
          {peakMonth.month}
        </p>
        <p className="text-xl text-cyan-200 mt-2">
          {isClub ? `${peakMonth.totalAttendance} total attendances` : `${peakMonth.count} runs`}
        </p>
      </motion.div>

      {/* Month bars */}
      <div className="w-full max-w-lg">
        <div className="flex items-end justify-between gap-1 h-32">
          {sortedMonths.map((m, index) => (
            <motion.div
              key={m.month}
              initial={{ height: 0 }}
              animate={{ height: `${(m.totalAttendance / maxAttendance) * 100}%` }}
              transition={{ delay: 0.5 + index * 0.05, duration: 0.5 }}
              className={`flex-1 rounded-t-lg ${
                m.month === peakMonth.month
                  ? 'bg-gradient-to-t from-amber-500 to-yellow-400'
                  : 'bg-white/20'
              }`}
              title={`${m.month}: ${m.totalAttendance} attendances`}
            />
          ))}
        </div>
        <div className="flex justify-between gap-1 mt-2">
          {sortedMonths.map(m => (
            <div
              key={m.month}
              className={`flex-1 text-center text-xs ${
                m.month === peakMonth.month ? 'text-amber-400 font-bold' : 'text-cyan-200/60'
              }`}
            >
              {m.month}
            </div>
          ))}
        </div>
      </div>

      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.5 }}
        className="mt-8 text-lg text-cream/80"
      >
        {peakMonth.month === 'Mar' ? "March madness!" :
         peakMonth.month === 'Jun' ? "Winter warriors!" :
         peakMonth.month === 'Sep' ? "Spring into action!" :
         "Consistency is key!"}
      </motion.p>
    </div>
  )
}
