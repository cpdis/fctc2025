import { useParams, Link, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import Header from '../components/Layout/Header'

export default function RunDetail({ data }) {
  const { runId } = useParams()
  const navigate = useNavigate()

  // Find the run by index
  const runIndex = parseInt(runId, 10)
  const run = data?.runs?.[runIndex]

  if (!run) {
    return (
      <div className="min-h-screen bg-cream">
        <Header />
        <main className="max-w-4xl mx-auto px-4 py-12 text-center">
          <h1 className="text-2xl font-bold text-espresso mb-4">Run not found</h1>
          <Link to="/" className="text-orange hover:underline">
            Back to Dashboard
          </Link>
        </main>
      </div>
    )
  }

  const attendees = run.attendees || []

  return (
    <div className="min-h-screen bg-cream">
      <Header />

      <main className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back button */}
        <button
          onClick={() => navigate(-1)}
          className="flex items-center gap-2 text-coffee hover:text-orange transition-colors mb-6"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back
        </button>

        {/* Run header */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-white rounded-2xl shadow-md p-6 mb-6"
        >
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div>
              <span className="px-3 py-1 rounded-full text-sm font-medium bg-pink/20 text-pink-dark">
                {run.runType}
              </span>
              <h1 className="text-2xl font-bold text-espresso mt-2">{run.date}</h1>
              <p className="text-coffee mt-1">{run.meet}</p>
            </div>

            <div className="flex gap-6">
              <div className="text-center">
                <div className="text-3xl font-bold text-orange">{run.totalAttendance}</div>
                <div className="text-sm text-coffee">Runners</div>
              </div>
              {run.actualKm && (
                <div className="text-center">
                  <div className="text-3xl font-bold text-mint-dark">{run.actualKm.toFixed(1)}</div>
                  <div className="text-sm text-coffee">Kilometers</div>
                </div>
              )}
            </div>
          </div>
        </motion.div>

        {/* Attendees list */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="bg-white rounded-2xl shadow-md p-6"
        >
          <h2 className="text-lg font-bold text-espresso mb-4">Who was there</h2>

          {attendees.length > 0 ? (
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
              {attendees.map((name, index) => (
                <motion.div
                  key={name}
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: index * 0.03 }}
                  className="flex items-center gap-3 p-3 bg-cream rounded-xl"
                >
                  <div className="w-10 h-10 rounded-full bg-gradient-to-br from-pink to-orange flex items-center justify-center text-white font-bold text-sm">
                    {name.charAt(0).toUpperCase()}
                  </div>
                  <span className="text-sm font-medium text-espresso truncate">{name}</span>
                </motion.div>
              ))}
            </div>
          ) : (
            <p className="text-coffee/60 text-center py-8">No attendees recorded for this run.</p>
          )}

          {run.plusOnes > 0 && (
            <div className="mt-4 pt-4 border-t border-cream-dark text-sm text-coffee">
              + {run.plusOnes} guest{run.plusOnes > 1 ? 's' : ''}
            </div>
          )}
        </motion.div>

        {/* Aggregate distance */}
        {run.aggregateKm && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="bg-white rounded-2xl shadow-md p-6 mt-6"
          >
            <h2 className="text-lg font-bold text-espresso mb-2">Combined Distance</h2>
            <p className="text-3xl font-bold text-mint-dark">
              {run.aggregateKm.toFixed(1)} km
            </p>
            <p className="text-sm text-coffee mt-1">
              Total kilometers run by all {run.totalAttendance} attendees
            </p>
          </motion.div>
        )}
      </main>
    </div>
  )
}
