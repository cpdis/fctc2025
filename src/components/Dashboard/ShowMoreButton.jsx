/**
 * The Poster "Show all" button under a truncated table: a mono outline button
 * that expands the list downward in place (no modal, no inner scrollbox).
 * Styled by `.more` in styles/poster.css, so it must sit inside `.poster`.
 *
 * @param {boolean} expanded   current state (drives the label)
 * @param {number} total       total row count (shown in the collapsed label)
 * @param {string} noun        plural noun for the rows, e.g. "members", "runs"
 * @param {() => void} onClick  toggle handler
 */
export default function ShowMoreButton({ expanded, total, noun = 'rows', onClick }) {
  return (
    <button type="button" className="more" onClick={onClick} aria-expanded={expanded}>
      {expanded ? 'Show fewer' : `Show all ${total} ${noun}`}
    </button>
  )
}
