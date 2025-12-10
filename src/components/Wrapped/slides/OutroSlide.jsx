import { motion } from 'framer-motion'
import { Link } from 'react-router-dom'

export default function OutroSlide({ stats, clubData, onRestart }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const summaryStats = isClub
    ? [
        { label: 'Total Runs', value: data.totalRuns },
        { label: 'Aggregate KM', value: `${Math.round(data.totalClubKm)}` },
        { label: 'Active Members', value: data.activeMembers },
      ]
    : [
        { label: 'Runs Attended', value: data.totalRuns },
        { label: 'Distance', value: `${Math.round(data.totalKm)} km` },
        { label: 'Club Rank', value: `#${data.rank}` },
      ]

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-navy via-navy-light to-pink-dark">
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", delay: 0.2 }}
        className="mb-6"
      >
        <img src="/fctc_logo.jpeg" alt="FCTC Logo" className="h-36 w-auto" />
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.4 }}
        className="text-center mb-8"
      >
        <h2 className="text-2xl text-mint mb-2">
          {isClub ? 'FCTC 2025' : `${data.name}'s 2025`}
        </h2>
        <p className="text-4xl md:text-5xl font-bold text-cream">
          What a Year!
        </p>
      </motion.div>

      {/* Summary stats */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.6 }}
        className="flex gap-6 mb-8"
      >
        {summaryStats.map((stat, index) => (
          <motion.div
            key={stat.label}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.7 + index * 0.1 }}
            className="text-center"
          >
            <div className="text-3xl font-bold text-cream">{stat.value}</div>
            <div className="text-sm text-mint">{stat.label}</div>
          </motion.div>
        ))}
      </motion.div>

      {/* Message */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1 }}
        className="text-center mb-10 max-w-md"
      >
        <p className="text-lg text-cream/80">
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
        transition={{ delay: 1.3 }}
        className="flex flex-col sm:flex-row gap-4"
      >
        <button
          onClick={onRestart}
          className="px-6 py-3 bg-white/10 text-cream rounded-full font-medium hover:bg-white/20 transition-colors flex items-center gap-2"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          View Another Member
        </button>

        <Link
          to="/"
          className="px-6 py-3 bg-orange text-cream rounded-full font-medium hover:bg-orange/80 transition-colors flex items-center gap-2"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
          </svg>
          Back to Dashboard
        </Link>
      </motion.div>

      {/* Footer */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.6 }}
        className="absolute bottom-8 text-center"
      >
        <p className="text-mint/60 text-sm">
          Filament Coffee Track Club
        </p>
        <p className="text-mint/40 text-xs mt-1">
          Keep running, keep caffeinating ☕
        </p>
      </motion.div>
    </div>
  )
}
