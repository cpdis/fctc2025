import { useState, useCallback, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Link } from 'react-router-dom'
import SlideProgress from './SlideProgress'

// Import all slides
import IntroSlide from './slides/IntroSlide'
import BigNumbersSlide from './slides/BigNumbersSlide'
import TopAttendeeSlide from './slides/TopAttendeeSlide'
import FavoriteRunSlide from './slides/FavoriteRunSlide'
import DistanceSlide from './slides/DistanceSlide'
import StreakSlide from './slides/StreakSlide'
import DayPreferenceSlide from './slides/DayPreferenceSlide'
import PeakMonthSlide from './slides/PeakMonthSlide'
import SpecialMomentsSlide from './slides/SpecialMomentsSlide'
import RegularsSlide from './slides/RegularsSlide'
import OutroSlide from './slides/OutroSlide'

const slideComponents = [
  IntroSlide,
  BigNumbersSlide,
  TopAttendeeSlide,
  FavoriteRunSlide,
  DistanceSlide,
  StreakSlide,
  DayPreferenceSlide,
  PeakMonthSlide,
  SpecialMomentsSlide,
  RegularsSlide,
  OutroSlide,
]

export default function WrappedContainer({ stats, clubData, onRestart }) {
  const [currentSlide, setCurrentSlide] = useState(0)
  const [direction, setDirection] = useState(1)

  const totalSlides = slideComponents.length

  const goToSlide = useCallback((index) => {
    if (index < 0 || index >= totalSlides) return
    setDirection(index > currentSlide ? 1 : -1)
    setCurrentSlide(index)
  }, [currentSlide, totalSlides])

  const nextSlide = useCallback(() => {
    if (currentSlide < totalSlides - 1) {
      setDirection(1)
      setCurrentSlide(prev => prev + 1)
    }
  }, [currentSlide, totalSlides])

  const prevSlide = useCallback(() => {
    if (currentSlide > 0) {
      setDirection(-1)
      setCurrentSlide(prev => prev - 1)
    }
  }, [currentSlide])

  // Keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'ArrowRight' || e.key === ' ') {
        e.preventDefault()
        nextSlide()
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault()
        prevSlide()
      } else if (e.key === 'Escape') {
        onRestart()
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [nextSlide, prevSlide, onRestart])

  // Touch/swipe handling
  const [touchStart, setTouchStart] = useState(null)

  const handleTouchStart = (e) => {
    setTouchStart(e.touches[0].clientX)
  }

  const handleTouchEnd = (e) => {
    if (!touchStart) return

    const touchEnd = e.changedTouches[0].clientX
    const diff = touchStart - touchEnd

    if (Math.abs(diff) > 50) {
      if (diff > 0) {
        nextSlide()
      } else {
        prevSlide()
      }
    }
    setTouchStart(null)
  }

  const CurrentSlideComponent = slideComponents[currentSlide]

  // Enhanced slide variants with subtle rotation for playfulness
  const slideVariants = {
    enter: (direction) => ({
      x: direction > 0 ? '100%' : '-100%',
      opacity: 0,
      scale: 0.95,
      rotate: direction > 0 ? 2 : -2,
    }),
    center: {
      x: 0,
      opacity: 1,
      scale: 1,
      rotate: 0,
    },
    exit: (direction) => ({
      x: direction > 0 ? '-100%' : '100%',
      opacity: 0,
      scale: 0.95,
      rotate: direction > 0 ? -2 : 2,
    }),
  }

  return (
    <div
      className="fixed top-0 left-0 right-0 h-dvh bg-navy overflow-hidden"
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
    >
      {/* Progress bar */}
      <SlideProgress
        current={currentSlide}
        total={totalSlides}
        onSlideClick={goToSlide}
      />

      {/* Back button */}
      <Link to="/">
        <motion.div
          className="absolute top-4 left-4 z-50 p-2.5 rounded-full bg-white/10 backdrop-blur-sm text-cream border border-white/10"
          whileHover={{ scale: 1.1, backgroundColor: 'rgba(255,255,255,0.2)' }}
          whileTap={{ scale: 0.9 }}
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.3 }}
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </motion.div>
      </Link>

      {/* Restart button */}
      <motion.button
        onClick={onRestart}
        className="absolute top-4 right-4 z-50 p-2.5 rounded-full bg-white/10 backdrop-blur-sm text-cream border border-white/10"
        title="Choose different member"
        whileHover={{ scale: 1.1, backgroundColor: 'rgba(255,255,255,0.2)' }}
        whileTap={{ scale: 0.9 }}
        initial={{ opacity: 0, x: 20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ delay: 0.3 }}
      >
        <motion.svg
          className="w-5 h-5"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          whileHover={{ rotate: 180 }}
          transition={{ duration: 0.3 }}
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </motion.svg>
      </motion.button>

      {/* Slides */}
      <AnimatePresence custom={direction} mode="wait">
        <motion.div
          key={currentSlide}
          custom={direction}
          variants={slideVariants}
          initial="enter"
          animate="center"
          exit="exit"
          transition={{
            x: { type: "spring", stiffness: 300, damping: 30 },
            opacity: { duration: 0.2 },
            scale: { type: "spring", stiffness: 300, damping: 25 },
            rotate: { type: "spring", stiffness: 300, damping: 25 }
          }}
          className="absolute inset-0"
        >
          <CurrentSlideComponent
            stats={stats}
            clubData={clubData}
            onNext={nextSlide}
            onRestart={onRestart}
            isLast={currentSlide === totalSlides - 1}
          />
        </motion.div>
      </AnimatePresence>

      {/* Navigation arrows */}
      <motion.div
        className="absolute bottom-4 sm:bottom-8 left-0 right-0 flex justify-center items-center gap-4 z-40"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5 }}
      >
        <motion.button
          onClick={prevSlide}
          disabled={currentSlide === 0}
          className={`p-3 rounded-full backdrop-blur-sm border transition-all ${
            currentSlide === 0
              ? 'bg-white/5 text-white/20 cursor-not-allowed border-white/5'
              : 'bg-white/10 text-cream border-white/10'
          }`}
          whileHover={currentSlide > 0 ? { scale: 1.1, x: -3 } : {}}
          whileTap={currentSlide > 0 ? { scale: 0.9 } : {}}
        >
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </motion.button>

        <motion.span
          className="text-mint text-sm font-medium tabular-nums bg-white/5 px-3 py-1.5 rounded-full backdrop-blur-sm"
          key={currentSlide}
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: "spring", stiffness: 400 }}
        >
          {currentSlide + 1} / {totalSlides}
        </motion.span>

        <motion.button
          onClick={nextSlide}
          disabled={currentSlide === totalSlides - 1}
          className={`p-3 rounded-full transition-all ${
            currentSlide === totalSlides - 1
              ? 'bg-white/5 text-white/20 cursor-not-allowed border border-white/5'
              : 'bg-gradient-to-r from-orange to-terracotta text-cream'
          }`}
          style={currentSlide < totalSlides - 1 ? {
            boxShadow: '0 4px 20px rgba(255, 81, 27, 0.3)'
          } : {}}
          whileHover={currentSlide < totalSlides - 1 ? { scale: 1.1, x: 3 } : {}}
          whileTap={currentSlide < totalSlides - 1 ? { scale: 0.9 } : {}}
        >
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
        </motion.button>
      </motion.div>

      {/* Keyboard hint - hidden on mobile */}
      <motion.div
        className="absolute bottom-1 left-0 right-0 text-center text-xs text-latte/40 hidden sm:block"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1 }}
      >
        Use arrow keys or swipe to navigate
      </motion.div>
    </div>
  )
}
