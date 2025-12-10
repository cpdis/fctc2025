import { useEffect, useState } from 'react'
import { motion, useSpring, useTransform } from 'framer-motion'

export default function AnimatedNumber({ value, duration = 2, delay = 0, suffix = '', prefix = '', decimals = 0 }) {
  const [isVisible, setIsVisible] = useState(false)
  const [hasAnimated, setHasAnimated] = useState(false)

  useEffect(() => {
    const timer = setTimeout(() => setIsVisible(true), delay * 1000)
    return () => clearTimeout(timer)
  }, [delay])

  // Bouncier spring physics for more playful feel
  const spring = useSpring(0, {
    stiffness: 80,
    damping: 20,
    mass: 0.5,
  })

  const display = useTransform(spring, (current) => {
    const rounded = Math.round(current * Math.pow(10, decimals)) / Math.pow(10, decimals)
    // Add thousands separator for large numbers
    const formatted = rounded >= 1000
      ? rounded.toLocaleString()
      : rounded.toString()
    return prefix + formatted + suffix
  })

  useEffect(() => {
    if (isVisible && !hasAnimated) {
      // Small delay before starting the count to build anticipation
      const timer = setTimeout(() => {
        spring.set(value)
        setHasAnimated(true)
      }, 100)
      return () => clearTimeout(timer)
    }
  }, [spring, value, isVisible, hasAnimated])

  return (
    <motion.span
      initial={{ opacity: 0, scale: 0.5, y: 20 }}
      animate={{
        opacity: isVisible ? 1 : 0,
        scale: isVisible ? 1 : 0.5,
        y: isVisible ? 0 : 20,
      }}
      transition={{
        duration: 0.4,
        delay,
        type: "spring",
        stiffness: 300,
        damping: 15
      }}
      className="inline-block tabular-nums"
    >
      {display}
    </motion.span>
  )
}
