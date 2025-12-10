import { motion } from 'framer-motion'

// Coffee bean shaped indicator
const CoffeeBean = ({ active, onClick, index }) => (
  <motion.button
    onClick={onClick}
    className="relative"
    whileHover={{ scale: 1.2 }}
    whileTap={{ scale: 0.9 }}
  >
    <motion.div
      className="w-3 h-4 rounded-full relative overflow-hidden"
      style={{
        background: active
          ? 'linear-gradient(135deg, #d4a574 0%, #b8956a 100%)'
          : 'rgba(255,255,255,0.2)',
        boxShadow: active ? '0 2px 8px rgba(212, 165, 116, 0.5)' : 'none',
      }}
      initial={false}
      animate={{
        scale: active ? 1 : 0.85,
      }}
      transition={{ type: "spring", stiffness: 400, damping: 15 }}
    >
      {/* Coffee bean line */}
      <motion.div
        className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-0.5 h-2 rounded-full"
        style={{
          background: active ? 'rgba(0,0,0,0.2)' : 'rgba(255,255,255,0.1)',
        }}
        initial={false}
        animate={{ opacity: active ? 1 : 0.5 }}
      />
    </motion.div>
    {/* Bounce animation when becoming active */}
    {active && (
      <motion.div
        className="absolute inset-0 rounded-full"
        style={{ background: 'rgba(212, 165, 116, 0.3)' }}
        initial={{ scale: 0.5, opacity: 1 }}
        animate={{ scale: 2, opacity: 0 }}
        transition={{ duration: 0.4 }}
      />
    )}
  </motion.button>
)

export default function SlideProgress({ current, total, onSlideClick }) {
  return (
    <div className="fixed top-0 left-0 right-0 z-50 p-4 pointer-events-none">
      <motion.div
        className="flex gap-2.5 justify-center items-center max-w-md mx-auto py-2 px-4 rounded-full bg-black/10 backdrop-blur-sm pointer-events-auto"
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5 }}
      >
        {Array.from({ length: total }).map((_, index) => (
          <CoffeeBean
            key={index}
            index={index}
            active={index <= current}
            onClick={() => onSlideClick(index)}
          />
        ))}
      </motion.div>
    </div>
  )
}
