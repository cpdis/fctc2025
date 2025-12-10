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

  const slideVariants = {
    enter: (direction) => ({
      x: direction > 0 ? '100%' : '-100%',
      opacity: 0,
    }),
    center: {
      x: 0,
      opacity: 1,
    },
    exit: (direction) => ({
      x: direction > 0 ? '-100%' : '100%',
      opacity: 0,
    }),
  }

  return (
    <div
      className="fixed inset-0 bg-navy overflow-hidden"
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
      <Link
        to="/"
        className="absolute top-4 left-4 z-50 p-2 rounded-full bg-white/10 text-cream hover:bg-white/20 transition-colors"
      >
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        </svg>
      </Link>

      {/* Restart button */}
      <button
        onClick={onRestart}
        className="absolute top-4 right-4 z-50 p-2 rounded-full bg-white/10 text-cream hover:bg-white/20 transition-colors"
        title="Choose different member"
      >
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
      </button>

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
            opacity: { duration: 0.2 }
          }}
          className="absolute inset-0"
        >
          <CurrentSlideComponent
            stats={stats}
            clubData={clubData}
            onNext={nextSlide}
            isLast={currentSlide === totalSlides - 1}
          />
        </motion.div>
      </AnimatePresence>

      {/* Navigation arrows */}
      <div className="absolute bottom-8 left-0 right-0 flex justify-center items-center gap-4 z-40">
        <button
          onClick={prevSlide}
          disabled={currentSlide === 0}
          className={`p-3 rounded-full transition-all ${
            currentSlide === 0
              ? 'bg-white/5 text-white/20 cursor-not-allowed'
              : 'bg-white/10 text-cream hover:bg-white/20'
          }`}
        >
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>

        <span className="text-mint text-sm">
          {currentSlide + 1} / {totalSlides}
        </span>

        <button
          onClick={nextSlide}
          disabled={currentSlide === totalSlides - 1}
          className={`p-3 rounded-full transition-all ${
            currentSlide === totalSlides - 1
              ? 'bg-white/5 text-white/20 cursor-not-allowed'
              : 'bg-orange text-cream hover:bg-orange/80'
          }`}
        >
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
        </button>
      </div>

      {/* Keyboard hint */}
      <div className="absolute bottom-2 left-0 right-0 text-center text-xs text-latte/40">
        Use arrow keys or swipe to navigate
      </div>
    </div>
  )
}
