import { motion } from 'framer-motion'
import AnimatedNumber from '../AnimatedNumber'

export default function BigNumbersSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const numbers = isClub
    ? [
        { label: 'Total Runs', value: data.totalRuns, suffix: '' },
        { label: 'Aggregate Distance', value: Math.round(data.totalClubKm), suffix: ' km' },
        { label: 'Total Attendance', value: data.totalAttendanceInstances, suffix: '' },
      ]
    : [
        { label: 'Runs Attended', value: data.totalRuns, suffix: '' },
        { label: 'Distance Covered', value: Math.round(data.totalKm), suffix: ' km' },
        { label: 'Attendance Rate', value: Math.round(data.attendanceRate), suffix: '%' },
      ]

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 bg-gradient-to-br from-mocha via-coffee to-terracotta">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-8"
      >
        <h2 className="text-2xl text-latte mb-2">
          {isClub ? 'The Club' : 'You'} in Numbers
        </h2>
        <p className="text-4xl md:text-5xl font-bold text-cream">
          What a Year!
        </p>
      </motion.div>

      <div className="grid gap-8 max-w-lg w-full">
        {numbers.map((item, index) => (
          <motion.div
            key={item.label}
            initial={{ opacity: 0, x: -50 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.3 + index * 0.3 }}
            className="text-center"
          >
            <div className="text-6xl md:text-8xl font-bold text-cream mb-2">
              <AnimatedNumber
                value={item.value}
                suffix={item.suffix}
                delay={0.5 + index * 0.3}
              />
            </div>
            <div className="text-xl text-latte">{item.label}</div>
          </motion.div>
        ))}
      </div>

      {isClub && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 2 }}
          className="mt-12 text-center"
        >
          <p className="text-lg text-cream/80">
            That's enough to run from Sydney to Brisbane... twice!
          </p>
        </motion.div>
      )}
    </div>
  )
}
