import { motion } from 'framer-motion'
import { Link } from 'react-router-dom'

// Coffee cup toast animation
const CoffeeCup = ({ side, delay }) => (
  <motion.div
    className="text-5xl"
    initial={{
      x: side === 'left' ? -60 : 60,
      rotate: side === 'left' ? -30 : 30,
      opacity: 0
    }}
    animate={{
      x: side === 'left' ? -10 : 10,
      rotate: side === 'left' ? -10 : 10,
      opacity: 1
    }}
    transition={{ delay, type: "spring", stiffness: 200, damping: 15 }}
  >
    <motion.span
      animate={{
        rotate: side === 'left' ? [-10, -5, -10] : [10, 5, 10],
      }}
      transition={{ duration: 1.5, repeat: Infinity, ease: "easeInOut" }}
    >
      ☕
    </motion.span>
  </motion.div>
)

// Steam animation for the coffee
const SteamWisp = ({ delay }) => (
  <motion.div
    className="absolute w-1 h-4 rounded-full bg-gradient-to-t from-cream/30 to-transparent"
    style={{ top: '-20px', left: '50%', transform: 'translateX(-50%)' }}
    initial={{ opacity: 0, y: 0 }}
    animate={{
      opacity: [0, 0.5, 0],
      y: [-5, -20],
    }}
    transition={{ duration: 1.5, delay, repeat: Infinity }}
  />
)

export default function OutroSlide({ stats, clubData, onRestart }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const summaryStats = isClub
    ? [
        { label: 'Total Runs', value: data.totalRuns, icon: '🏃' },
        { label: 'Aggregate KM', value: `${Math.round(data.totalClubKm)}`, icon: '📍' },
        { label: 'Active Members', value: data.activeMembers, icon: '👥' },
      ]
    : [
        { label: 'Runs Attended', value: data.totalRuns, icon: '✓' },
        { label: 'Distance', value: `${Math.round(data.totalKm)} km`, icon: '📍' },
        { label: 'Club Rank', value: `#${data.rank}`, icon: '🏆' },
      ]

  return (
    <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-24 sm:p-8 bg-gradient-to-br from-navy via-navy-light to-pink-dark relative overflow-hidden">
      {/* Animated background elements */}
      <motion.div
        className="absolute top-20 right-20 w-64 h-64 rounded-full opacity-15"
        style={{ background: 'radial-gradient(circle, #fa688e 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.2, 1],
          opacity: [0.1, 0.2, 0.1],
        }}
        transition={{ duration: 6, repeat: Infinity, ease: "easeInOut" }}
      />
      <motion.div
        className="absolute bottom-32 left-20 w-48 h-48 rounded-full opacity-10"
        style={{ background: 'radial-gradient(circle, #9ed1af 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.3, 1],
        }}
        transition={{ duration: 8, repeat: Infinity, ease: "easeInOut", delay: 2 }}
      />

      {/* Coffee toast animation */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.5 }}
        className="flex items-center gap-4 mb-6 relative z-10"
      >
        <CoffeeCup side="left" delay={0.6} />
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: "spring", delay: 0.2 }}
          className="relative"
        >
          <motion.img
            src="/fctc_logo.jpeg"
            alt="FCTC Logo"
            className="h-32 w-auto rounded-2xl shadow-2xl"
            whileHover={{ scale: 1.05 }}
          />
          <SteamWisp delay={0} />
          <SteamWisp delay={0.5} />
          <SteamWisp delay={1} />
        </motion.div>
        <CoffeeCup side="right" delay={0.7} />
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.9, type: "spring" }}
        className="text-center mb-8 relative z-10"
      >
        <motion.h2
          className="font-display text-2xl text-mint mb-2"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1 }}
        >
          {isClub ? 'FCTC 2025' : `${data.name}'s 2025`}
        </motion.h2>
        <motion.p
          className="font-display text-4xl md:text-5xl font-bold text-cream"
          initial={{ scaleY: 0.5, scaleX: 1.2 }}
          animate={{ scaleY: 1, scaleX: 1 }}
          transition={{ delay: 1.1, type: "spring", stiffness: 300 }}
        >
          What a Year!
        </motion.p>
      </motion.div>

      {/* Summary stats */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.2 }}
        className="flex gap-4 sm:gap-6 mb-8 relative z-10"
      >
        {summaryStats.map((stat, index) => (
          <motion.div
            key={stat.label}
            initial={{ opacity: 0, y: 20, scale: 0.9 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={{ delay: 1.3 + index * 0.1, type: "spring" }}
            whileHover={{ scale: 1.05 }}
            className="text-center bg-white/5 backdrop-blur-sm rounded-xl px-4 py-3 border border-white/10"
          >
            <motion.div
              className="text-2xl mb-1"
              animate={{ rotate: [0, 5, -5, 0] }}
              transition={{ duration: 2, repeat: Infinity, delay: index * 0.3 }}
            >
              {stat.icon}
            </motion.div>
            <div className="font-display text-2xl sm:text-3xl font-bold text-cream">{stat.value}</div>
            <div className="text-xs sm:text-sm text-mint">{stat.label}</div>
          </motion.div>
        ))}
      </motion.div>

      {/* Message */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.6 }}
        className="text-center mb-10 max-w-md relative z-10"
      >
        <p className="text-lg text-cream/90">
          {isClub
            ? "Here's to more kilometers, more coffee, and more community in the year ahead!"
            : "Keep running, keep showing up, and we'll see you at the next run!"
          }
        </p>
      </motion.div>

      {/* Actions */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 1.8 }}
        className="flex flex-col sm:flex-row gap-4 relative z-10"
      >
        <motion.button
          onClick={onRestart}
          whileHover={{ scale: 1.05, y: -2 }}
          whileTap={{ scale: 0.95 }}
          className="px-6 py-3 bg-white/10 backdrop-blur-sm text-cream rounded-full font-medium border border-white/20 flex items-center gap-2"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          View Another Member
        </motion.button>

        <Link to="/">
          <motion.div
            whileHover={{ scale: 1.05, y: -2 }}
            whileTap={{ scale: 0.95 }}
            className="px-6 py-3 bg-gradient-to-r from-orange to-terracotta text-cream rounded-full font-medium flex items-center gap-2 relative overflow-hidden"
            style={{
              boxShadow: '0 8px 30px rgba(255, 81, 27, 0.3)'
            }}
          >
            {/* Shimmer effect */}
            <motion.div
              className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent -translate-x-full"
              animate={{ x: ['calc(-100%)', 'calc(200%)'] }}
              transition={{ duration: 2, repeat: Infinity, repeatDelay: 3 }}
            />
            <svg className="w-5 h-5 relative z-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
            </svg>
            <span className="relative z-10">Back to Dashboard</span>
          </motion.div>
        </Link>
      </motion.div>

      {/* Footer */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 2 }}
        className="absolute bottom-8 text-center"
      >
        <p className="text-mint/70 text-sm font-medium">
          Filament Coffee Track Club
        </p>
        <motion.p
          className="text-mint/50 text-xs mt-1"
          animate={{ opacity: [0.5, 0.8, 0.5] }}
          transition={{ duration: 3, repeat: Infinity }}
        >
          Keep running, keep caffeinating ☕
        </motion.p>
      </motion.div>
    </div>
  )
}
