import { motion } from 'framer-motion'

export default function IntroSlide({ stats, onNext }) {
  const isClub = stats.type === 'club'
  const name = isClub ? 'FCTC' : stats.data.name

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-navy via-navy-light to-pink-dark">
      <motion.div
        initial={{ scale: 0, rotate: -180 }}
        animate={{ scale: 1, rotate: 0 }}
        transition={{ type: "spring", duration: 1, delay: 0.2 }}
        className="mb-8"
      >
        <img src="/fctc_logo.jpeg" alt="FCTC Logo" className="h-40 w-auto" />
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 30 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5 }}
        className="text-center"
      >
        <h1 className="text-5xl md:text-7xl font-bold text-cream mb-4">
          {isClub ? 'FCTC' : name}
        </h1>

        <motion.div
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.8 }}
          className="inline-block"
        >
          <span className="text-2xl md:text-4xl font-bold bg-gradient-to-r from-pink to-orange bg-clip-text text-transparent">
            2025 Wrapped
          </span>
        </motion.div>

        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1.2 }}
          className="mt-6 text-lg text-mint"
        >
          {isClub
            ? "A year of runs, coffee, and community"
            : "Your year of running with FCTC"
          }
        </motion.p>
      </motion.div>

      <motion.button
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 1.5 }}
        onClick={onNext}
        className="mt-12 px-8 py-4 bg-orange text-cream font-bold rounded-full hover:bg-orange/80 transition-colors shadow-lg"
      >
        Let's Go
      </motion.button>

      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 2 }}
        className="absolute bottom-24 text-mint/60 text-sm"
      >
        Tap or swipe to continue
      </motion.div>
    </div>
  )
}
