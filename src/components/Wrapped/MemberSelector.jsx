import { useState } from 'react'
import { motion } from 'framer-motion'
import { Link } from 'react-router-dom'

// Playful rank badge component for member cards
const RankBadge = ({ rank }) => {
  if (rank === 1) {
    return (
      <motion.div
        className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold relative"
        style={{
          background: 'linear-gradient(135deg, #fbbf24 0%, #f59e0b 100%)',
          boxShadow: '0 2px 8px rgba(245, 158, 11, 0.5)'
        }}
        whileHover={{ scale: 1.1, rotate: [0, -5, 5, 0] }}
      >
        <span className="text-yellow-900">1</span>
        <motion.span
          className="absolute -top-1.5 text-yellow-400"
          animate={{ y: [0, -2, 0] }}
          transition={{ duration: 1.5, repeat: Infinity }}
        >
          <svg className="w-3 h-3" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 1L9 9L1 8L7 14L5 22L12 18L19 22L17 14L23 8L15 9L12 1Z" />
          </svg>
        </motion.span>
      </motion.div>
    )
  }

  if (rank === 2) {
    return (
      <div
        className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold"
        style={{
          background: 'linear-gradient(135deg, #e5e7eb 0%, #9ca3af 100%)',
          boxShadow: '0 2px 6px rgba(156, 163, 175, 0.4)'
        }}
      >
        <span className="text-gray-700">2</span>
      </div>
    )
  }

  if (rank === 3) {
    return (
      <div
        className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold"
        style={{
          background: 'linear-gradient(135deg, #d97706 0%, #b45309 100%)',
          boxShadow: '0 2px 6px rgba(180, 83, 9, 0.4)'
        }}
      >
        <span className="text-white">3</span>
      </div>
    )
  }

  return (
    <div className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold bg-white/20 text-cream/80">
      {rank}
    </div>
  )
}

export default function MemberSelector({ members, memberTotals, onSelect }) {
  const [searchTerm, setSearchTerm] = useState('')

  // Sort members by attendance
  const sortedMembers = [...members]
    .filter(m => memberTotals[m]?.totalRuns > 0)
    .sort((a, b) => (memberTotals[b]?.totalRuns || 0) - (memberTotals[a]?.totalRuns || 0))

  const filteredMembers = searchTerm
    ? sortedMembers.filter(m => m.toLowerCase().includes(searchTerm.toLowerCase()))
    : sortedMembers

  return (
    <div className="min-h-screen bg-gradient-to-br from-navy via-navy-light to-pink-dark flex flex-col relative overflow-hidden">
      {/* Animated background blobs */}
      <motion.div
        className="absolute top-20 -right-20 w-64 h-64 rounded-full opacity-20"
        style={{ background: 'radial-gradient(circle, #fa688e 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.2, 1],
          x: [0, 20, 0],
          y: [0, -10, 0],
        }}
        transition={{ duration: 8, repeat: Infinity, ease: "easeInOut" }}
      />
      <motion.div
        className="absolute bottom-40 -left-20 w-48 h-48 rounded-full opacity-15"
        style={{ background: 'radial-gradient(circle, #9ed1af 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.3, 1],
          x: [0, 15, 0],
        }}
        transition={{ duration: 6, repeat: Infinity, ease: "easeInOut", delay: 1 }}
      />

      {/* Header */}
      <div className="p-4 relative z-10">
        <Link to="/" className="inline-flex items-center gap-2 text-amber-light hover:text-cream transition-colors font-medium">
          <motion.svg
            className="w-5 h-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            whileHover={{ x: -3 }}
            transition={{ type: "spring", stiffness: 400 }}
          >
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </motion.svg>
          Back to Dashboard
        </Link>
      </div>

      {/* Main content */}
      <div className="flex-1 flex flex-col items-center justify-center p-6 relative z-10">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center mb-8"
        >
          <motion.div
            initial={{ scale: 0, rotate: -10 }}
            animate={{ scale: 1, rotate: 0 }}
            transition={{ type: "spring", delay: 0.2, stiffness: 200 }}
            className="mx-auto mb-6"
          >
            <motion.img
              src="/fctc_logo.jpeg"
              alt="FCTC Logo"
              className="h-28 w-auto rounded-2xl shadow-2xl"
              whileHover={{ scale: 1.05, rotate: [0, -3, 3, 0] }}
              transition={{ duration: 0.4 }}
            />
          </motion.div>

          <h1 className="font-display text-4xl md:text-5xl font-bold text-cream mb-3 tracking-tight">
            FCTC 2025 Wrapped
          </h1>
          <p className="text-amber-light text-lg font-medium">
            Your year in running, coffee-style
          </p>
        </motion.div>

        {/* Club Stats Button */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
          onClick={() => onSelect('club')}
          whileHover={{ scale: 1.02, y: -2 }}
          whileTap={{ scale: 0.98 }}
          className="w-full max-w-md mb-6 p-5 rounded-2xl bg-gradient-to-r from-orange via-terracotta to-pink text-white font-bold text-lg relative overflow-hidden group"
          style={{
            boxShadow: '0 8px 30px rgba(255, 81, 27, 0.3), 0 4px 12px rgba(255, 81, 27, 0.2)'
          }}
        >
          {/* Shimmer effect */}
          <motion.div
            className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent -translate-x-full"
            animate={{ x: ['calc(-100%)', 'calc(200%)'] }}
            transition={{ duration: 2, repeat: Infinity, repeatDelay: 3 }}
          />
          <div className="flex items-center justify-center gap-3 relative z-10">
            <motion.svg
              className="w-6 h-6"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              animate={{ rotate: [0, 10, -10, 0] }}
              transition={{ duration: 2, repeat: Infinity, repeatDelay: 2 }}
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
            </motion.svg>
            View Club Wrapped
          </div>
          <p className="text-sm opacity-90 mt-1.5 font-normal relative z-10">See the whole club's 2025 stats</p>
        </motion.button>

        {/* Divider */}
        <div className="flex items-center gap-4 w-full max-w-md mb-6">
          <div className="flex-1 h-px bg-gradient-to-r from-transparent via-amber/40 to-transparent"></div>
          <span className="text-amber-light/80 text-sm font-medium">or choose your name</span>
          <div className="flex-1 h-px bg-gradient-to-r from-transparent via-amber/40 to-transparent"></div>
        </div>

        {/* Search */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4 }}
          className="w-full max-w-md mb-4"
        >
          <div className="relative">
            <input
              type="text"
              placeholder="Search members..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full px-4 py-3.5 pl-12 rounded-xl bg-white/10 backdrop-blur-sm border border-white/20 text-cream placeholder:text-cream/40 focus:outline-none focus:ring-2 focus:ring-amber/50 focus:border-transparent transition-all"
            />
            <svg className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-cream/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </motion.div>

        {/* Member list */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5 }}
          className="w-full max-w-md max-h-72 overflow-y-auto rounded-2xl bg-white/5 backdrop-blur-sm border border-white/10"
          style={{
            boxShadow: '0 4px 30px rgba(0, 0, 0, 0.2)'
          }}
        >
          {filteredMembers.map((member, index) => (
            <motion.button
              key={member}
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.5 + index * 0.02 }}
              onClick={() => onSelect(member)}
              whileHover={{ backgroundColor: 'rgba(255,255,255,0.1)', x: 4 }}
              className="w-full px-4 py-3.5 flex items-center justify-between transition-colors border-b border-white/5 last:border-0"
            >
              <div className="flex items-center gap-3">
                <RankBadge rank={index + 1} />
                <span className="text-cream font-medium">{member}</span>
              </div>
              <div className="text-right text-sm">
                <div className="text-amber-light font-semibold">{memberTotals[member]?.totalRuns || 0} runs</div>
                <div className="text-cream/50">{memberTotals[member]?.totalKm?.toFixed(0) || 0} km</div>
              </div>
            </motion.button>
          ))}
        </motion.div>
      </div>
    </div>
  )
}
