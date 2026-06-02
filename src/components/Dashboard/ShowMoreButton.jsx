/**
 * Quiet, full-width toggle shown beneath a truncated table. Expands the list
 * downward in place (no modal, no inner scrollbox). Uses the shared design
 * tokens so it reads identically in light and dark.
 *
 * @param {boolean} expanded   current state (drives label + chevron direction)
 * @param {number} total       total row count (shown in the collapsed label)
 * @param {string} noun        plural noun for the rows, e.g. "members", "runs"
 * @param {() => void} onClick  toggle handler
 */
export default function ShowMoreButton({ expanded, total, noun = 'rows', onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-expanded={expanded}
      className="mt-3 w-full flex items-center justify-center gap-1.5 rounded-lg border border-border py-2 text-sm font-medium text-ink-muted hover:text-ink hover:bg-surface transition-colors"
    >
      {expanded ? 'Show fewer' : `Show all ${total} ${noun}`}
      <svg
        className={`h-4 w-4 transition-transform ${expanded ? 'rotate-180' : ''}`}
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        aria-hidden="true"
      >
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
      </svg>
    </button>
  )
}
