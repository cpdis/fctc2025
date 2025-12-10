import { motion } from 'framer-motion'

export default function SlideProgress({ current, total, onSlideClick }) {
  return (
    <div className="absolute top-0 left-0 right-0 z-50 p-4">
      <div className="flex gap-1 max-w-md mx-auto">
        {Array.from({ length: total }).map((_, index) => (
          <button
            key={index}
            onClick={() => onSlideClick(index)}
            className="flex-1 h-1 rounded-full overflow-hidden bg-white/20 hover:bg-white/30 transition-colors"
          >
            <motion.div
              initial={false}
              animate={{
                width: index < current ? '100%' : index === current ? '100%' : '0%'
              }}
              transition={{ duration: 0.3 }}
              className={`h-full rounded-full ${
                index <= current ? 'bg-pink' : 'bg-transparent'
              }`}
            />
          </button>
        ))}
      </div>
    </div>
  )
}
