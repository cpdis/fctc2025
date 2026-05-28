import { useParams, Link, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import Header from '../components/Layout/Header'
import { getRunTypeDisplayName, dataColors } from '../utils/theme'

export default function RunDetail({ data }) {
  const { runId } = useParams()
  const navigate = useNavigate()

  // Find the run by index
  const runIndex = parseInt(runId, 10)
  const run = data?.runs?.[runIndex]

  if (!run) {
    return (
      <div className="min-h-screen bg-surface text-ink">
        <Header />
        <main className="max-w-4xl mx-auto px-4 py-12 text-center">
          <h1 className="font-display text-2xl font-semibold text-ink mb-4">Run not found</h1>
          <Link to="/" className="text-ink-muted hover:text-ink underline">
            Back to Dashboard
          </Link>
        </main>
      </div>
    )
  }

  const attendees = run.attendees || []

  return (
    <div className="min-h-screen bg-surface text-ink">
      <Header />

      <main className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Back button */}
        <button
          onClick={() => navigate(-1)}
          className="flex items-center gap-2 text-ink-muted hover:text-ink transition-colors mb-6"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back
        </button>

        {/* Run header */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.35, ease: 'easeOut' }}
          className="card-clean p-6 mb-6"
        >
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div>
              <span className="px-2.5 py-1 rounded-md text-xs font-medium text-ink bg-surface border border-border">
                {getRunTypeDisplayName(run.runType)}
              </span>
              <h1 className="font-display text-2xl font-semibold text-ink mt-2">{run.date}</h1>
              <p className="text-ink-muted mt-1">{run.meet}</p>
            </div>

            <div className="flex gap-8">
              <div className="text-center">
                <div className="font-display text-3xl font-semibold text-ink tabular-nums">{run.totalAttendance}</div>
                <div className="text-sm text-ink-muted">Runners</div>
              </div>
              {run.actualKm && (
                <div className="text-center">
                  <div className="font-display text-3xl font-semibold text-ink tabular-nums">{run.actualKm.toFixed(1)}</div>
                  <div className="text-sm text-ink-muted">Kilometers</div>
                </div>
              )}
            </div>
          </div>
        </motion.div>

        {/* Attendees list */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.35, delay: 0.06, ease: 'easeOut' }}
          className="card-clean p-6"
        >
          <h2 className="font-display text-lg font-semibold text-ink mb-4">Who was there</h2>

          {attendees.length > 0 ? (
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
              {attendees.map((name) => (
                <div
                  key={name}
                  className="flex items-center gap-3 p-3 bg-surface rounded-lg border border-border"
                >
                  <div
                    className="w-9 h-9 rounded-full flex items-center justify-center text-card font-semibold text-sm flex-shrink-0"
                    style={{ background: dataColors[0] }}
                  >
                    {name.charAt(0).toUpperCase()}
                  </div>
                  <span className="text-sm text-ink truncate">{name}</span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-ink-muted text-center py-8">No attendees recorded for this run.</p>
          )}

          {run.plusOnes > 0 && (
            <div className="mt-4 pt-4 border-t border-border text-sm text-ink-muted">
              + {run.plusOnes} guest{run.plusOnes > 1 ? 's' : ''}
            </div>
          )}
        </motion.div>

        {/* Aggregate distance */}
        {run.aggregateKm && (
          <motion.div
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35, delay: 0.12, ease: 'easeOut' }}
            className="card-clean p-6 mt-6"
          >
            <h2 className="font-display text-lg font-semibold text-ink mb-2">Combined Distance</h2>
            <p className="font-display text-3xl font-semibold text-ink tabular-nums">
              {run.aggregateKm.toFixed(1)} km
            </p>
            <p className="text-sm text-ink-muted mt-1">
              Total kilometers run by all {run.totalAttendance} attendees
            </p>
          </motion.div>
        )}
      </main>
    </div>
  )
}
