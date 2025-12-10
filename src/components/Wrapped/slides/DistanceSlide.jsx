import { motion } from 'framer-motion'
import AnimatedNumber from '../AnimatedNumber'

export default function DistanceSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const totalKm = isClub ? data.totalClubKm : data.totalKm
  const avgPerRun = isClub
    ? data.totalClubKm / data.totalRuns
    : data.avgKmPerRun

  // Fun comparisons with accurate Australian road distances
  // Sydney to Perth: 3,934 km
  // Sydney to Melbourne: 877 km
  // Sydney to Brisbane: 918 km
  // Sydney to Canberra: 286 km
  // Great Ocean Road: 243 km
  // Marathon: 42.195 km
  const getComparison = (km) => {
    if (km >= 7800) return { text: `That's like running from Sydney to Perth and back!`, emoji: '🦘' }
    if (km >= 3900) return { text: `You could run from Sydney to Perth!`, emoji: '🗺️' }
    if (km >= 1800) return { text: `That's Sydney to Brisbane and back!`, emoji: '🌴' }
    if (km >= 900) return { text: `You could run from Sydney to Brisbane!`, emoji: '🌴' }
    if (km >= 850) return { text: `That's almost Sydney to Melbourne!`, emoji: '🏙️' }
    if (km >= 280) return { text: `You could run from Sydney to Canberra!`, emoji: '🏛️' }
    if (km >= 200) return { text: `That's almost the Great Ocean Road end to end!`, emoji: '🛣️' }
    if (km >= 84) return { text: `That's ${Math.floor(km / 42.195)} marathons worth!`, emoji: '🏅' }
    if (km >= 42) return { text: `That's a full marathon distance!`, emoji: '🏃' }
    return { text: `Every kilometer counts!`, emoji: '💪' }
  }

  const comparison = getComparison(totalKm)

  return (
    <div className="min-h-screen-ios flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-emerald-900 via-teal-800 to-cyan-700">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-6"
      >
        <h2 className="text-2xl text-emerald-200 mb-2">Distance Covered</h2>
        <p className="text-3xl md:text-4xl font-bold text-cream">
          {isClub ? 'The Club Ran' : 'You Ran'}
        </p>
      </motion.div>

      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", delay: 0.3 }}
        className="text-center mb-8"
      >
        <div className="text-7xl md:text-9xl font-bold text-cream">
          <AnimatedNumber value={Math.round(totalKm)} delay={0.5} />
        </div>
        <div className="text-3xl text-emerald-200 font-medium">kilometers</div>
      </motion.div>

      {/* Track visualization */}
      <motion.div
        initial={{ scaleX: 0 }}
        animate={{ scaleX: 1 }}
        transition={{ delay: 1, duration: 1.5, ease: "easeOut" }}
        className="w-full max-w-md h-4 bg-white/20 rounded-full overflow-hidden mb-8"
      >
        <motion.div
          initial={{ width: 0 }}
          animate={{ width: '100%' }}
          transition={{ delay: 1.2, duration: 1.5, ease: "easeOut" }}
          className="h-full bg-gradient-to-r from-emerald-400 to-cyan-400 rounded-full"
        />
      </motion.div>

      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.5 }}
        className="text-center space-y-4"
      >
        <div className="flex items-center justify-center gap-3 px-6 py-3 bg-white/10 rounded-full">
          <span className="text-4xl">{comparison.emoji}</span>
          <span className="text-lg text-cream">{comparison.text}</span>
        </div>

        <p className="text-xl text-emerald-200">
          Averaging {avgPerRun.toFixed(1)} km per run
        </p>
      </motion.div>

      {!isClub && data.distanceRank && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 2 }}
          className="mt-8 text-center"
        >
          <p className="text-lg text-cream/80">
            You're <span className="font-bold text-emerald-300">#{data.distanceRank}</span> in total distance
          </p>
        </motion.div>
      )}
    </div>
  )
}
