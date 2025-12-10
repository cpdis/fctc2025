import { useEffect, useState } from 'react'
import { motion, useSpring, useTransform } from 'framer-motion'

export default function AnimatedNumber({ value, duration = 2, delay = 0, suffix = '', prefix = '', decimals = 0 }) {
  const [isVisible, setIsVisible] = useState(false)

  useEffect(() => {
    const timer = setTimeout(() => setIsVisible(true), delay * 1000)
    return () => clearTimeout(timer)
  }, [delay])

  const spring = useSpring(0, {
    stiffness: 50,
    damping: 30,
  })

  const display = useTransform(spring, (current) =>
    prefix + Math.round(current * Math.pow(10, decimals)) / Math.pow(10, decimals) + suffix
  )

  useEffect(() => {
    if (isVisible) {
      spring.set(value)
    }
  }, [spring, value, isVisible])

  return (
    <motion.span
      initial={{ opacity: 0, scale: 0.5 }}
      animate={{ opacity: isVisible ? 1 : 0, scale: isVisible ? 1 : 0.5 }}
      transition={{ duration: 0.5, delay }}
    >
      {display}
    </motion.span>
  )
}
