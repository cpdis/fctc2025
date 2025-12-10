import { motion } from 'framer-motion'

const cardVariants = {
  hidden: { opacity: 0, y: 30, scale: 0.95 },
  visible: (i) => ({
    opacity: 1,
    y: 0,
    scale: 1,
    transition: {
      delay: i * 0.1,
      type: "spring",
      stiffness: 300,
      damping: 20
    }
  })
}

const iconVariants = {
  hover: {
    rotate: [0, -10, 10, -5, 5, 0],
    transition: { duration: 0.5 }
  }
}

export default function StatsCards({ totalRuns, totalKm, activeMembers, avgAttendance, filteredStats, isFiltered }) {
  const stats = [
    {
      label: 'Total Runs',
      value: isFiltered ? filteredStats.totalRuns : totalRuns,
      fullValue: totalRuns,
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
        </svg>
      ),
      gradient: 'from-terracotta to-orange',
      iconBg: 'bg-gradient-to-br from-terracotta/20 to-orange/10'
    },
    {
      label: 'Aggregate Distance',
      value: isFiltered ? `${filteredStats.totalKm.toFixed(0)}` : `${totalKm.toFixed(0)}`,
      fullValue: totalKm.toFixed(0),
      suffix: 'km',
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
        </svg>
      ),
      gradient: 'from-pink to-coffee',
      iconBg: 'bg-gradient-to-br from-pink/20 to-coffee/10'
    },
    {
      label: 'Active Members',
      value: activeMembers,
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
        </svg>
      ),
      gradient: 'from-navy-light to-mocha',
      iconBg: 'bg-gradient-to-br from-navy-light/20 to-mocha/10'
    },
    {
      label: 'Avg Attendance',
      value: isFiltered ? filteredStats.avgAttendance.toFixed(1) : avgAttendance.toFixed(1),
      fullValue: avgAttendance.toFixed(1),
      suffix: '/run',
      icon: (
        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        </svg>
      ),
      gradient: 'from-mint to-mint-dark',
      iconBg: 'bg-gradient-to-br from-mint/20 to-mint-dark/10'
    }
  ]

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
      {stats.map((stat, i) => (
        <motion.div
          key={stat.label}
          custom={i}
          initial="hidden"
          animate="visible"
          whileHover="hover"
          variants={cardVariants}
          className="relative bg-white rounded-2xl overflow-hidden group cursor-default"
          style={{
            boxShadow: `
              0 1px 2px rgba(2, 9, 18, 0.04),
              0 4px 12px rgba(2, 9, 18, 0.06)
            `
          }}
        >
          {/* Subtle gradient accent on top */}
          <div className={`absolute top-0 left-0 right-0 h-1 bg-gradient-to-r ${stat.gradient} opacity-80`} />

          {/* Hover glow effect */}
          <div className={`absolute inset-0 bg-gradient-to-br ${stat.gradient} opacity-0 group-hover:opacity-[0.03] transition-opacity duration-300`} />

          <div className="p-5 relative">
            <div className="flex items-center justify-between mb-3">
              <motion.span
                variants={iconVariants}
                className={`${stat.iconBg} text-espresso p-2.5 rounded-xl`}
              >
                {stat.icon}
              </motion.span>
              {isFiltered && stat.fullValue && (
                <span className="text-xs text-coffee/50 font-medium">of {stat.fullValue}</span>
              )}
            </div>
            <div className="mt-2">
              <span className="font-display text-3xl font-bold text-espresso tracking-tight">
                {stat.value}
              </span>
              {stat.suffix && (
                <span className="text-lg text-coffee/60 ml-1 font-medium">{stat.suffix}</span>
              )}
            </div>
            <p className="text-sm text-coffee/70 mt-1 font-medium">{stat.label}</p>
          </div>

          {/* Subtle lift on hover */}
          <motion.div
            className="absolute inset-0 pointer-events-none"
            initial={{ boxShadow: "0 0 0 0 transparent" }}
            whileHover={{
              boxShadow: "0 8px 30px rgba(2, 9, 18, 0.08)",
              transition: { duration: 0.2 }
            }}
          />
        </motion.div>
      ))}
    </div>
  )
}
