import { Link, useLocation } from 'react-router-dom'
import { motion } from 'framer-motion'

export default function Header() {
  const location = useLocation()
  const isWrapped = location.pathname.startsWith('/wrapped')

  return (
    <motion.header
      initial={{ y: -20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      className="bg-navy text-cream sticky top-0 z-50 shadow-lg"
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <Link to="/" className="flex items-center gap-3 group">
            <img
              src="/fctc_logo.jpeg"
              alt="FCTC Logo"
              className="h-10 w-auto group-hover:scale-110 transition-transform"
            />
            <div>
              <h1 className="font-bold text-lg leading-tight">Filament Coffee Track Club</h1>
              <p className="text-xs text-mint">2025 Season</p>
            </div>
          </Link>

          <nav className="flex items-center gap-4">
            <Link
              to="/"
              className={`px-4 py-2 rounded-lg font-medium transition-colors ${
                !isWrapped
                  ? 'bg-pink text-navy'
                  : 'text-mint hover:text-cream hover:bg-navy-light'
              }`}
            >
              Dashboard
            </Link>
            <Link
              to="/wrapped"
              className={`px-4 py-2 rounded-lg font-medium transition-colors flex items-center gap-2 ${
                isWrapped
                  ? 'bg-orange text-cream'
                  : 'text-mint hover:text-cream hover:bg-navy-light'
              }`}
            >
              <span>2025 Wrapped</span>
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5m0 0l-5 5m5-5H6" />
              </svg>
            </Link>
          </nav>
        </div>
      </div>
    </motion.header>
  )
}
