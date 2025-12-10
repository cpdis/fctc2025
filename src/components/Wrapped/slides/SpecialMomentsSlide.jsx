import { motion } from 'framer-motion'

export default function SpecialMomentsSlide({ stats, clubData }) {
  const isClub = stats.type === 'club'
  const data = stats.data

  const specialRuns = clubData.runs.filter(run => {
    const type = run.runType.toLowerCase()
    return type.includes('half') || type.includes('mara') ||
           type.includes('cup') || type.includes('pancake') ||
           type.includes('10k')
  })

  const events = [
    {
      name: 'Invasion Day',
      date: 'Jan 27',
      emoji: '🇦🇺',
      runs: specialRuns.filter(r => r.runType.includes('Invasion'))
    },
    {
      name: 'Good Friday Pancake',
      date: 'Apr 18',
      emoji: '🥞',
      runs: specialRuns.filter(r => r.runType.includes('Pancake'))
    },
    {
      name: 'Anzac Day',
      date: 'Apr 25',
      emoji: '🎖️',
      runs: specialRuns.filter(r => r.runType.includes('Anzac'))
    },
    {
      name: 'Filament Cup',
      date: 'Jun 25',
      emoji: '🏆',
      runs: specialRuns.filter(r => r.runType.includes('Cup'))
    },
    {
      name: 'Beer Run Half',
      date: 'Sep 20',
      emoji: '🍺',
      runs: specialRuns.filter(r => r.runType.includes('Beer'))
    },
  ].filter(e => e.runs.length > 0)

  if (isClub) {
    return (
      <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-rose-900 via-pink-800 to-purple-700">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center mb-8"
        >
          <h2 className="text-2xl text-rose-200 mb-2">Special Moments</h2>
          <p className="text-4xl md:text-5xl font-bold text-cream">
            The Big Events
          </p>
        </motion.div>

        <div className="space-y-4 w-full max-w-md">
          {events.map((event, index) => (
            <motion.div
              key={event.name}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.3 + index * 0.15 }}
              className="flex items-center gap-4 p-4 rounded-2xl bg-white/10"
            >
              <span className="text-4xl">{event.emoji}</span>
              <div className="flex-1">
                <div className="font-bold text-lg text-cream">{event.name}</div>
                <div className="text-sm text-rose-200">{event.date}</div>
              </div>
              <div className="text-right">
                <div className="font-bold text-2xl text-cream">
                  {event.runs.reduce((sum, r) => sum + r.totalAttendance, 0)}
                </div>
                <div className="text-sm text-rose-200">runners</div>
              </div>
            </motion.div>
          ))}
        </div>

        {data.marathonFinishers?.length > 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 1.5 }}
            className="mt-8 text-center"
          >
            <p className="text-xl text-cream mb-2">🎖️ Marathon Finishers</p>
            <p className="text-rose-200">
              {data.marathonFinishers.join(', ')}
            </p>
          </motion.div>
        )}
      </div>
    )
  }

  // Individual member view
  const memberEvents = data.specialEvents || []

  if (memberEvents.length === 0) {
    return (
      <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-rose-900 via-pink-800 to-purple-700">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center"
        >
          <span className="text-8xl mb-6 block">🎯</span>
          <h2 className="text-2xl text-rose-200 mb-2">Special Events</h2>
          <p className="text-3xl font-bold text-cream mb-4">
            Next Year's Goals?
          </p>
          <p className="text-lg text-cream/80">
            There are some amazing special events coming up!
          </p>
        </motion.div>
      </div>
    )
  }

  return (
    <div className="min-h-dvh flex flex-col items-center justify-center p-4 pb-20 sm:p-8 bg-gradient-to-br from-rose-900 via-pink-800 to-purple-700">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center mb-8"
      >
        <h2 className="text-2xl text-rose-200 mb-2">Special Moments</h2>
        <p className="text-4xl md:text-5xl font-bold text-cream">
          You Showed Up!
        </p>
      </motion.div>

      <div className="space-y-4 w-full max-w-md">
        {memberEvents.map((run, index) => {
          const emoji = run.runType.includes('Mara') ? '🎖️' :
                        run.runType.includes('Half') ? '🏃' :
                        run.runType.includes('Cup') ? '🏆' :
                        run.runType.includes('Pancake') ? '🥞' : '⭐'
          return (
            <motion.div
              key={`${run.date}-${run.runType}`}
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.3 + index * 0.15 }}
              className="flex items-center gap-4 p-4 rounded-2xl bg-white/10"
            >
              <span className="text-4xl">{emoji}</span>
              <div className="flex-1">
                <div className="font-bold text-lg text-cream">{run.runType}</div>
                <div className="text-sm text-rose-200">{run.date}</div>
              </div>
              <div className="text-right text-cream">
                {run.actualKm?.toFixed(1)} km
              </div>
            </motion.div>
          )
        })}
      </div>

      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.5 }}
        className="mt-8 text-lg text-cream/80"
      >
        {memberEvents.some(e => e.runType.toLowerCase().includes('mara'))
          ? "Marathon legend! 🏆"
          : "Showing up when it counts!"}
      </motion.p>
    </div>
  )
}
