import { useState } from 'react'
import { motion } from 'framer-motion'
import { Link } from 'react-router-dom'

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
    <div className="min-h-screen bg-gradient-to-br from-navy via-navy-light to-pink-dark flex flex-col">
      {/* Header */}
      <div className="p-4">
        <Link to="/" className="inline-flex items-center gap-2 text-mint hover:text-cream transition-colors">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </svg>
          Back to Dashboard
        </Link>
      </div>

      {/* Main content */}
      <div className="flex-1 flex flex-col items-center justify-center p-6">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center mb-8"
        >
          <motion.div
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            transition={{ type: "spring", delay: 0.2 }}
            className="mx-auto mb-6"
          >
            <img src="/fctc_logo.jpeg" alt="FCTC Logo" className="h-32 w-auto" />
          </motion.div>

          <h1 className="text-4xl md:text-5xl font-bold text-cream mb-3">
            FCTC 2025 Wrapped
          </h1>
          <p className="text-mint text-lg">
            Your year in running, coffee-style
          </p>
        </motion.div>

        {/* Club Stats Button */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
          onClick={() => onSelect('club')}
          className="w-full max-w-md mb-6 p-4 rounded-2xl bg-gradient-to-r from-orange to-pink text-white font-bold text-lg shadow-lg hover:shadow-xl transform hover:scale-[1.02] transition-all"
        >
          <div className="flex items-center justify-center gap-3">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
            </svg>
            View Club Wrapped
          </div>
          <p className="text-sm opacity-80 mt-1">See the whole club's 2025 stats</p>
        </motion.button>

        {/* Divider */}
        <div className="flex items-center gap-4 w-full max-w-md mb-6">
          <div className="flex-1 h-px bg-mint/30"></div>
          <span className="text-mint text-sm">or choose your name</span>
          <div className="flex-1 h-px bg-mint/30"></div>
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
              className="w-full px-4 py-3 pl-11 rounded-xl bg-white/10 border border-mint/30 text-cream placeholder:text-mint/60 focus:outline-none focus:ring-2 focus:ring-pink focus:border-transparent"
            />
            <svg className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-mint/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </motion.div>

        {/* Member list */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5 }}
          className="w-full max-w-md max-h-64 overflow-y-auto rounded-xl bg-white/5 border border-mint/20"
        >
          {filteredMembers.map((member, index) => (
            <motion.button
              key={member}
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.5 + index * 0.02 }}
              onClick={() => onSelect(member)}
              className="w-full px-4 py-3 flex items-center justify-between hover:bg-white/10 transition-colors border-b border-mint/10 last:border-0"
            >
              <div className="flex items-center gap-3">
                <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold ${
                  index < 3 ? 'bg-pink text-white' : 'bg-mint/30 text-cream'
                }`}>
                  {index + 1}
                </div>
                <span className="text-cream font-medium">{member}</span>
              </div>
              <div className="text-right text-sm">
                <div className="text-mint">{memberTotals[member]?.totalRuns || 0} runs</div>
                <div className="text-mint/60">{memberTotals[member]?.totalKm?.toFixed(0) || 0} km</div>
              </div>
            </motion.button>
          ))}
        </motion.div>
      </div>
    </div>
  )
}
