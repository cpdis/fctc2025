import { motion } from 'framer-motion'
import { getMemberTitle } from '../../../utils/calculations'

export default function TopAttendeeSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  if (isClub) {
    const top5 = data.leaderboard.slice(0, 5)

    return (
      <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-amber-900 via-yellow-800 to-amber-600">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center mb-8"
        >
          <h2 className="text-2xl text-amber-200 mb-2">The Legends</h2>
          <p className="text-4xl md:text-5xl font-bold text-cream">
            Most Dedicated Runners
          </p>
        </motion.div>

        <div className="space-y-4 w-full max-w-md">
          {top5.map((member, index) => (
            <motion.div
              key={member.name}
              initial={{ opacity: 0, x: -50, scale: 0.8 }}
              animate={{ opacity: 1, x: 0, scale: 1 }}
              transition={{ delay: 0.3 + index * 0.15 }}
              className={`flex items-center gap-4 p-4 rounded-2xl ${
                index === 0 ? 'bg-gradient-to-r from-yellow-500 to-amber-400 shadow-lg scale-105' :
                index === 1 ? 'bg-gradient-to-r from-gray-400 to-gray-300' :
                index === 2 ? 'bg-gradient-to-r from-amber-700 to-amber-600' :
                'bg-white/10'
              }`}
            >
              <div className={`w-12 h-12 rounded-full flex items-center justify-center font-bold text-xl ${
                index === 0 ? 'bg-yellow-900 text-yellow-300' :
                index === 1 ? 'bg-gray-600 text-gray-200' :
                index === 2 ? 'bg-amber-900 text-amber-200' :
                'bg-white/20 text-cream'
              }`}>
                {index === 0 ? '👑' : index + 1}
              </div>
              <div className="flex-1">
                <div className={`font-bold text-lg ${index < 3 ? 'text-espresso' : 'text-cream'}`}>
                  {member.name}
                </div>
              </div>
              <div className={`text-right ${index < 3 ? 'text-espresso' : 'text-cream'}`}>
                <div className="font-bold text-2xl">{member.totalRuns}</div>
                <div className="text-sm opacity-70">runs</div>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    )
  }

  // Individual member view
  const rank = data.rank
  const title = getMemberTitle(data)

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-amber-900 via-yellow-800 to-amber-600">
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", delay: 0.2 }}
        className="w-32 h-32 mb-6 rounded-full bg-gradient-to-br from-yellow-400 to-amber-500 flex items-center justify-center shadow-2xl"
      >
        {rank === 1 ? (
          <span className="text-6xl">👑</span>
        ) : (
          <span className="text-5xl font-bold text-amber-900">#{rank}</span>
        )}
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5 }}
        className="text-center"
      >
        <h2 className="text-2xl text-amber-200 mb-2">You ranked</h2>
        <p className="text-6xl md:text-8xl font-bold text-cream mb-4">
          #{rank}
        </p>
        <p className="text-xl text-amber-200">
          out of {clubData.leaderboard.length} runners
        </p>
      </motion.div>

      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1 }}
        className="mt-8 px-6 py-3 bg-white/10 rounded-full"
      >
        <span className="text-lg text-cream font-medium">
          {title}
        </span>
      </motion.div>

      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.5 }}
        className="mt-8 text-center text-cream/80"
      >
        <p className="text-3xl font-bold">{data.totalRuns} runs attended</p>
      </motion.div>
    </div>
  )
}
