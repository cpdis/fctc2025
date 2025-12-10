import { motion } from 'framer-motion'
import { getMemberTitle } from '../../../utils/calculations'

// Confetti particle component
const ConfettiParticle = ({ delay, color }) => {
  const randomX = Math.random() * 100
  const randomRotation = Math.random() * 360
  const size = 8 + Math.random() * 8

  return (
    <motion.div
      className="absolute rounded-sm"
      style={{
        width: size,
        height: size * 0.4,
        backgroundColor: color,
        left: `${randomX}%`,
        top: '-10%',
      }}
      initial={{ y: 0, rotate: 0, opacity: 1 }}
      animate={{
        y: '120vh',
        rotate: randomRotation + 720,
        opacity: [1, 1, 0],
      }}
      transition={{
        duration: 3 + Math.random() * 2,
        delay: delay,
        ease: "easeIn"
      }}
    />
  )
}

// Animated crown component
const AnimatedCrown = () => (
  <motion.div
    className="relative"
    initial={{ scale: 0, rotate: -30 }}
    animate={{ scale: 1, rotate: 0 }}
    transition={{ type: "spring", stiffness: 300, damping: 12, delay: 0.3 }}
  >
    <motion.span
      className="text-6xl"
      animate={{
        y: [0, -8, 0],
        rotate: [0, -5, 5, 0],
      }}
      transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
    >
      👑
    </motion.span>
    {/* Sparkles around crown */}
    {[0, 1, 2].map((i) => (
      <motion.div
        key={i}
        className="absolute w-2 h-2 bg-yellow-300 rounded-full"
        style={{
          top: `${20 + i * 25}%`,
          left: `${10 + i * 35}%`,
        }}
        animate={{
          scale: [0, 1, 0],
          opacity: [0, 1, 0],
        }}
        transition={{
          duration: 1.5,
          delay: 0.5 + i * 0.3,
          repeat: Infinity,
          repeatDelay: 1,
        }}
      />
    ))}
  </motion.div>
)

// Playful rank badge
const RankBadge = ({ rank, isTop3 }) => {
  if (rank === 1) return <AnimatedCrown />

  const bgColor = rank === 2
    ? 'linear-gradient(135deg, #e5e7eb 0%, #9ca3af 100%)'
    : rank === 3
    ? 'linear-gradient(135deg, #d97706 0%, #b45309 100%)'
    : 'rgba(255,255,255,0.2)'

  return (
    <motion.div
      className="w-12 h-12 rounded-full flex items-center justify-center font-display font-bold text-xl"
      style={{ background: bgColor }}
      initial={{ scale: 0 }}
      animate={{ scale: 1 }}
      transition={{ type: "spring", stiffness: 400, damping: 15 }}
      whileHover={{ scale: 1.1 }}
    >
      <span className={rank <= 3 ? 'text-espresso' : 'text-cream'}>{rank}</span>
    </motion.div>
  )
}

export default function TopAttendeeSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const confettiColors = ['#fbbf24', '#f59e0b', '#d97706', '#fa688e', '#ff511b']

  if (isClub) {
    const top5 = data.leaderboard.slice(0, 5)

    return (
      <div className="min-h-screen-ios flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-amber-900 via-yellow-800 to-amber-600 relative overflow-hidden">
        {/* Confetti for club view */}
        {confettiColors.map((color, i) =>
          [...Array(4)].map((_, j) => (
            <ConfettiParticle key={`${i}-${j}`} delay={0.5 + j * 0.3} color={color} />
          ))
        )}

        <motion.div
          initial={{ opacity: 0, y: -30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: "spring" }}
          className="text-center mb-8 relative z-10"
        >
          <motion.h2
            className="font-display text-2xl text-amber-200 mb-2"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.2 }}
          >
            The Legends
          </motion.h2>
          <motion.p
            className="font-display text-4xl md:text-5xl font-bold text-cream"
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ delay: 0.3, type: "spring" }}
          >
            Most Dedicated Runners
          </motion.p>
        </motion.div>

        <div className="space-y-4 w-full max-w-md relative z-10">
          {top5.map((member, index) => (
            <motion.div
              key={member.name}
              initial={{ opacity: 0, x: -60, rotate: -2 }}
              animate={{ opacity: 1, x: 0, rotate: 0 }}
              transition={{
                delay: 0.4 + index * 0.12,
                type: "spring",
                stiffness: 200,
                damping: 15
              }}
              whileHover={{ scale: 1.02, x: 8 }}
              className={`flex items-center gap-4 p-4 rounded-2xl border border-white/10 backdrop-blur-sm ${
                index === 0 ? 'bg-gradient-to-r from-yellow-500/90 to-amber-400/90 shadow-xl' :
                index === 1 ? 'bg-gradient-to-r from-gray-400/90 to-gray-300/90' :
                index === 2 ? 'bg-gradient-to-r from-amber-700/90 to-amber-600/90' :
                'bg-white/10'
              }`}
              style={{
                boxShadow: index === 0 ? '0 8px 32px rgba(251, 191, 36, 0.4)' : undefined
              }}
            >
              <RankBadge rank={index + 1} isTop3={index < 3} />
              <div className="flex-1">
                <div className={`font-display font-bold text-lg ${index < 3 ? 'text-espresso' : 'text-cream'}`}>
                  {member.name}
                </div>
              </div>
              <div className={`text-right ${index < 3 ? 'text-espresso' : 'text-cream'}`}>
                <motion.div
                  className="font-display font-bold text-2xl"
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ delay: 0.6 + index * 0.1, type: "spring" }}
                >
                  {member.totalRuns}
                </motion.div>
                <div className="text-sm opacity-70">runs</div>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    )
  }

  // Individual member view
  const rank = data.rank
  const title = getMemberTitle(data)

  return (
    <div className="min-h-screen-ios flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-amber-900 via-yellow-800 to-amber-600 relative overflow-hidden">
      {/* Confetti for top 3 */}
      {rank <= 3 && confettiColors.map((color, i) =>
        [...Array(5)].map((_, j) => (
          <ConfettiParticle key={`${i}-${j}`} delay={0.3 + j * 0.2} color={color} />
        ))
      )}

      {/* Animated background glow */}
      <motion.div
        className="absolute w-96 h-96 rounded-full opacity-30"
        style={{ background: 'radial-gradient(circle, #fbbf24 0%, transparent 70%)' }}
        animate={{
          scale: [1, 1.2, 1],
          opacity: [0.2, 0.35, 0.2],
        }}
        transition={{ duration: 3, repeat: Infinity, ease: "easeInOut" }}
      />

      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", stiffness: 200, damping: 15, delay: 0.2 }}
        className="w-36 h-36 mb-6 rounded-full bg-gradient-to-br from-yellow-400 to-amber-500 flex items-center justify-center relative z-10"
        style={{
          boxShadow: '0 12px 40px rgba(251, 191, 36, 0.5), 0 6px 20px rgba(251, 191, 36, 0.3)'
        }}
      >
        {rank === 1 ? (
          <AnimatedCrown />
        ) : (
          <motion.span
            className="font-display text-5xl font-bold text-amber-900"
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            transition={{ delay: 0.4, type: "spring" }}
          >
            #{rank}
          </motion.span>
        )}
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5, type: "spring" }}
        className="text-center relative z-10"
      >
        <h2 className="font-display text-2xl text-amber-200 mb-2">You ranked</h2>
        <motion.p
          className="font-display text-6xl md:text-8xl font-bold text-cream mb-4"
          initial={{ scaleY: 0.5, scaleX: 1.2 }}
          animate={{ scaleY: 1, scaleX: 1 }}
          transition={{ delay: 0.6, type: "spring", stiffness: 300 }}
        >
          #{rank}
        </motion.p>
        <p className="text-xl text-amber-200">
          out of {clubData.leaderboard.length} runners
        </p>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, scale: 0.8 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ delay: 1, type: "spring" }}
        className="mt-8 px-6 py-3 bg-white/15 backdrop-blur-sm rounded-full border border-white/20 relative z-10"
      >
        <span className="text-lg text-cream font-medium">
          {title}
        </span>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 1.5 }}
        className="mt-8 text-center text-cream/90 relative z-10"
      >
        <motion.p
          className="font-display text-3xl font-bold"
          initial={{ scale: 0.9 }}
          animate={{ scale: 1 }}
          transition={{ delay: 1.6, type: "spring" }}
        >
          {data.totalRuns} runs attended
        </motion.p>
      </motion.div>
    </div>
  )
}
