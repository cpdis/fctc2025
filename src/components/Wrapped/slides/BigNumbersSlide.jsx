import { motion } from 'framer-motion'
import AnimatedNumber from '../AnimatedNumber'

// Accurate Australian road distances (km)
// Sydney to Perth: 3,934 km
// Sydney to Melbourne: 877 km
// Sydney to Brisbane: 918 km
// Sydney to Canberra: 286 km
// Marathon: 42.195 km
const getDistanceComparison = (km) => {
  if (km >= 7800) return `That's like running from Sydney to Perth and back!`
  if (km >= 3900) return `That's enough to run from Sydney to Perth!`
  if (km >= 1800) return `That's like running Sydney to Brisbane... twice!`
  if (km >= 900) return `That's enough to run from Sydney to Brisbane!`
  if (km >= 850) return `That's almost Sydney to Melbourne!`
  if (km >= 280) return `That's enough to run from Sydney to Canberra!`
  if (km >= 84) return `That's ${Math.floor(km / 42.195)} marathons worth!`
  return `Every kilometer counts!`
}

// Squash and stretch animation for playful number reveals
const squashStretch = {
  initial: { scaleY: 0.3, scaleX: 1.4, opacity: 0, y: 30 },
  animate: {
    scaleY: 1,
    scaleX: 1,
    opacity: 1,
    y: 0,
    transition: { type: "spring", stiffness: 300, damping: 12 }
  }
}

// Card entrance with slight tilt
const cardVariant = {
  initial: { opacity: 0, x: -60, rotate: -3 },
  animate: (i) => ({
    opacity: 1,
    x: 0,
    rotate: 0,
    transition: {
      delay: 0.3 + i * 0.25,
      type: "spring",
      stiffness: 200,
      damping: 15
    }
  })
}

export default function BigNumbersSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const numbers = isClub
    ? [
        { label: 'Total Runs', value: data.totalRuns, suffix: '', icon: '🏃' },
        { label: 'Aggregate Distance', value: Math.round(data.totalClubKm), suffix: ' km', icon: '📍' },
        { label: 'Total Attendance', value: data.totalAttendanceInstances, suffix: '', icon: '👥' },
      ]
    : [
        { label: 'Runs Attended', value: data.totalRuns, suffix: '', icon: '✓' },
        { label: 'Distance Covered', value: Math.round(data.totalKm), suffix: ' km', icon: '📍' },
        { label: 'Attendance Rate', value: Math.round(data.attendanceRate), suffix: '%', icon: '📊' },
      ]

  return (
    <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-mocha via-coffee to-terracotta relative overflow-hidden">
      {/* Animated background shapes */}
      <motion.div
        className="absolute top-10 right-10 w-32 h-32 rounded-full opacity-20"
        style={{ background: 'radial-gradient(circle, #f2eee2 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.2, 1],
          rotate: [0, 90, 0],
        }}
        transition={{ duration: 10, repeat: Infinity, ease: "easeInOut" }}
      />
      <motion.div
        className="absolute bottom-20 left-10 w-24 h-24 rounded-full opacity-15"
        style={{ background: 'radial-gradient(circle, #d4a574 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.3, 1],
          y: [0, -20, 0],
        }}
        transition={{ duration: 8, repeat: Infinity, ease: "easeInOut", delay: 1 }}
      />

      <motion.div
        initial={{ opacity: 0, y: -30 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 200 }}
        className="text-center mb-10 relative z-10"
      >
        <motion.h2
          className="font-display text-2xl text-amber-light mb-2 tracking-wide"
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.1 }}
        >
          {isClub ? 'The Club' : 'You'} in Numbers
        </motion.h2>
        <motion.p
          className="font-display text-4xl md:text-5xl font-bold text-cream"
          {...squashStretch}
        >
          What a Year!
        </motion.p>
      </motion.div>

      <div className="grid gap-6 max-w-lg w-full relative z-10">
        {numbers.map((item, index) => (
          <motion.div
            key={item.label}
            custom={index}
            variants={cardVariant}
            initial="initial"
            animate="animate"
            whileHover={{ scale: 1.02, rotate: 1 }}
            className="relative bg-white/10 backdrop-blur-sm rounded-2xl p-6 border border-white/10 overflow-hidden"
            style={{
              boxShadow: '0 8px 32px rgba(0,0,0,0.2)'
            }}
          >
            {/* Accent bar */}
            <div
              className="absolute top-0 left-0 right-0 h-1 rounded-t-2xl"
              style={{
                background: index === 0 ? 'linear-gradient(90deg, #ff511b, #fa688e)' :
                           index === 1 ? 'linear-gradient(90deg, #d4a574, #e8c9a4)' :
                           'linear-gradient(90deg, #9ed1af, #78b896)'
              }}
            />

            <div className="flex items-center gap-4">
              <motion.div
                className="text-4xl"
                animate={{ rotate: [0, 10, -10, 0] }}
                transition={{ duration: 2, repeat: Infinity, delay: index * 0.5 }}
              >
                {item.icon}
              </motion.div>
              <div className="flex-1">
                <motion.div
                  className="font-display text-5xl md:text-6xl font-bold text-cream"
                  initial={{ scaleY: 0.5, scaleX: 1.2 }}
                  animate={{ scaleY: 1, scaleX: 1 }}
                  transition={{ type: "spring", stiffness: 300, damping: 10, delay: 0.5 + index * 0.25 }}
                >
                  <AnimatedNumber
                    value={item.value}
                    suffix={item.suffix}
                    delay={0.5 + index * 0.25}
                  />
                </motion.div>
                <div className="text-lg text-amber-light font-medium">{item.label}</div>
              </div>
            </div>
          </motion.div>
        ))}
      </div>

      {isClub && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 2.2, type: "spring" }}
          className="mt-10 text-center relative z-10"
        >
          <motion.p
            className="text-lg text-cream/90 bg-white/10 backdrop-blur-sm px-6 py-3 rounded-full border border-white/10"
            whileHover={{ scale: 1.05 }}
          >
            {getDistanceComparison(data.totalClubKm)}
          </motion.p>
        </motion.div>
      )}
    </div>
  )
}
