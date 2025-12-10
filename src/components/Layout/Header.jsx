import { Link, useLocation } from 'react-router-dom'
import { motion } from 'framer-motion'

export default function Header() {
  const location = useLocation()
  const isWrapped = location.pathname.startsWith('/wrapped')

  return (
    <motion.header
      initial={{ y: -20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      className="bg-navy text-cream sticky top-0 z-50 relative overflow-hidden"
    >
      {/* Subtle grain texture */}
      <div className="absolute inset-0 opacity-[0.03] pointer-events-none">
        <svg className="w-full h-full">
          <filter id="headerNoise">
            <feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="4" stitchTiles="stitch"/>
          </filter>
          <rect width="100%" height="100%" filter="url(#headerNoise)"/>
        </svg>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="flex items-center justify-between h-16">
          <Link to="/" className="flex items-center gap-2 sm:gap-3 group">
            <motion.div
              whileHover={{ rotate: [0, -5, 5, 0], transition: { duration: 0.5 } }}
              className="relative flex-shrink-0"
            >
              <img
                src="/fctc_logo.jpeg"
                alt="FCTC Logo"
                className="h-8 sm:h-10 w-auto rounded-lg shadow-lg"
              />
            </motion.div>
            <div className="min-w-0">
              <h1 className="font-display font-bold text-sm sm:text-lg leading-tight tracking-tight">
                <span className="sm:hidden">FCTC</span>
                <span className="hidden sm:inline">Filament Coffee Track Club</span>
              </h1>
              <p className="text-xs text-amber-light font-medium">2025 Season</p>
            </div>
          </Link>

          <nav className="flex items-center gap-2">
            <Link
              to="/"
              className="relative px-4 py-2 rounded-xl font-medium transition-all duration-300 group"
            >
              <span className={`relative z-10 ${!isWrapped ? 'text-navy' : 'text-cream/80 group-hover:text-cream'}`}>
                Dashboard
              </span>
              {!isWrapped && (
                <motion.div
                  layoutId="navPill"
                  className="absolute inset-0 bg-gradient-to-r from-pink to-pink-dark rounded-xl"
                  transition={{ type: "spring", stiffness: 400, damping: 30 }}
                />
              )}
              {isWrapped && (
                <span className="absolute bottom-1 left-4 right-4 h-0.5 bg-cream/30 rounded-full scale-x-0 group-hover:scale-x-100 transition-transform origin-left" />
              )}
            </Link>
            <Link
              to="/wrapped"
              className="relative px-4 py-2 rounded-xl font-medium transition-all duration-300 flex items-center gap-2 group"
            >
              <span className={`relative z-10 ${isWrapped ? 'text-cream' : 'text-cream/80 group-hover:text-cream'}`}>
                2025 Wrapped
              </span>
              <motion.svg
                className={`w-4 h-4 relative z-10 ${isWrapped ? 'text-cream' : 'text-cream/60 group-hover:text-cream'}`}
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                whileHover={{ x: 3 }}
                transition={{ type: "spring", stiffness: 400 }}
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5m0 0l-5 5m5-5H6" />
              </motion.svg>
              {isWrapped && (
                <motion.div
                  layoutId="navPill"
                  className="absolute inset-0 bg-gradient-to-r from-orange to-terracotta rounded-xl"
                  transition={{ type: "spring", stiffness: 400, damping: 30 }}
                />
              )}
              {!isWrapped && (
                <span className="absolute bottom-1 left-4 right-4 h-0.5 bg-cream/30 rounded-full scale-x-0 group-hover:scale-x-100 transition-transform origin-left" />
              )}
            </Link>
          </nav>
        </div>
      </div>

      {/* Warm bottom edge glow */}
      <div className="absolute bottom-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-amber/30 to-transparent" />
    </motion.header>
  )
}
