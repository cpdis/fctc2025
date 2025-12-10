import { motion } from 'framer-motion'

// Coffee steam animation component
const SteamWisp = ({ delay, x }) => (
  <motion.div
    className="absolute w-2 rounded-full bg-gradient-to-t from-cream/40 to-transparent"
    style={{ left: x, bottom: '100%', height: 20 }}
    initial={{ opacity: 0, y: 0, scaleY: 0.5 }}
    animate={{
      opacity: [0, 0.6, 0],
      y: [-5, -35],
      scaleY: [0.5, 1.2],
      x: [0, (Math.random() - 0.5) * 15],
    }}
    transition={{
      duration: 2,
      delay,
      repeat: Infinity,
      ease: "easeOut"
    }}
  />
)

export default function IntroSlide({ stats, onNext }) {
  const isClub = stats.type === 'club'
  const name = isClub ? 'FCTC' : stats.data.name

  return (
    <div className="min-h-screen-ios flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-navy via-navy-light to-pink-dark relative overflow-hidden">
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

      {/* Logo with steam effect */}
      <motion.div
        initial={{ scale: 0, rotate: -180 }}
        animate={{ scale: 1, rotate: 0 }}
        transition={{ type: "spring", stiffness: 200, damping: 15, delay: 0.2 }}
        className="mb-8 relative"
      >
        {/* Steam wisps */}
        <div className="absolute inset-0">
          <SteamWisp delay={0} x="30%" />
          <SteamWisp delay={0.5} x="50%" />
          <SteamWisp delay={1} x="70%" />
        </div>
        <motion.img
          src="/fctc_logo.jpeg"
          alt="FCTC Logo"
          className="h-40 w-auto rounded-2xl shadow-2xl relative z-10"
          whileHover={{ scale: 1.05, rotate: [0, -3, 3, 0] }}
          transition={{ duration: 0.4 }}
        />
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 30 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5, type: "spring" }}
        className="text-center relative z-10"
      >
        <motion.h1
          className="font-display text-5xl md:text-7xl font-bold text-cream mb-4 tracking-tight"
          initial={{ opacity: 0, y: 20, scaleY: 0.8 }}
          animate={{ opacity: 1, y: 0, scaleY: 1 }}
          transition={{ delay: 0.6, type: "spring", stiffness: 200 }}
        >
          {isClub ? 'FCTC' : name}
        </motion.h1>

        <motion.div
          initial={{ opacity: 0, scale: 0.5, rotate: -5 }}
          animate={{ opacity: 1, scale: 1, rotate: 0 }}
          transition={{ delay: 0.8, type: "spring", stiffness: 300 }}
          className="inline-block"
        >
          <span className="font-display text-2xl md:text-4xl font-bold bg-gradient-to-r from-pink via-orange to-amber bg-clip-text text-transparent">
            2025 Wrapped
          </span>
        </motion.div>

        <motion.p
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1.2 }}
          className="mt-6 text-lg text-mint font-medium"
        >
          {isClub
            ? "A year of runs, coffee, and community"
            : "Your year of running with FCTC"
          }
        </motion.p>
      </motion.div>

      <motion.button
        initial={{ opacity: 0, y: 20, scale: 0.9 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ delay: 1.5, type: "spring" }}
        onClick={onNext}
        whileHover={{ scale: 1.05, y: -2 }}
        whileTap={{ scale: 0.95 }}
        className="mt-12 px-8 py-4 bg-gradient-to-r from-orange to-terracotta text-cream font-bold rounded-full transition-colors relative overflow-hidden"
        style={{
          boxShadow: '0 8px 30px rgba(255, 81, 27, 0.4), 0 4px 12px rgba(255, 81, 27, 0.2)'
        }}
      >
        {/* Shimmer effect */}
        <motion.div
          className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent -translate-x-full"
          animate={{ x: ['calc(-100%)', 'calc(200%)'] }}
          transition={{ duration: 2, repeat: Infinity, repeatDelay: 3 }}
        />
        <span className="relative z-10">Let's Go</span>
      </motion.button>

      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 2 }}
        className="absolute bottom-24 text-mint/60 text-sm"
      >
        <motion.span
          animate={{ y: [0, 5, 0] }}
          transition={{ duration: 1.5, repeat: Infinity }}
        >
          Tap or swipe to continue
        </motion.span>
      </motion.div>
    </div>
  )
}
