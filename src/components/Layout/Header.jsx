import { Link, useLocation, useSearchParams } from 'react-router-dom'
import { YEAR_OPTIONS, resolveYear, isAllTime } from '../../config/years'

// Clean, minimal dashboard header.
//
// Layout: logo + club name on the left, nav (Dashboard | 2025 Wrapped) and the
// year switcher on the right. The switcher is a dropdown (years + "All time")
// that writes the selection into the URL (?year=YYYY or ?year=all); App.jsx
// reads it back via useSearchParams. Active controls use the single dark ink
// accent, everything else is muted grey on a white surface.
export default function Header() {
  const location = useLocation()
  const isWrapped = location.pathname.startsWith('/wrapped') ||
    location.pathname.startsWith('/2025wrapped')

  // Read the current selection from the URL (defaults to the latest valid year).
  const [searchParams, setSearchParams] = useSearchParams()
  const selectedYear = resolveYear(searchParams.get('year'))

  // Sub-label under the club name: "All Time" for the combined view, otherwise
  // "<year> Season".
  const seasonLabel = isAllTime(selectedYear) ? 'All Time' : `${selectedYear} Season`

  // Set ?year while preserving any other query params already in the URL.
  const selectYear = (year) => {
    const next = new URLSearchParams(searchParams)
    next.set('year', String(year))
    setSearchParams(next)
  }

  return (
    <header className="sticky top-0 z-50 bg-card border-b border-border">
      <div className="max-w-7xl 2xl:max-w-[1680px] mx-auto px-4 sm:px-6 lg:px-8">
        {/* On mobile the controls drop to a second row so nothing overlaps or
            gets clipped; from sm up everything sits on one 64px row. */}
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between sm:h-16 gap-2 sm:gap-4 py-2.5 sm:py-0">
          {/* Logo + name */}
          <Link to={`/?year=${selectedYear}`} className="flex items-center gap-3 min-w-0">
            <img
              src="/fctc_logo.jpeg"
              alt="FCTC Logo"
              className="h-9 w-auto rounded-lg flex-shrink-0"
            />
            <div className="min-w-0">
              <h1 className="font-display font-semibold text-sm sm:text-base leading-tight tracking-tight text-ink truncate">
                <span className="sm:hidden">FCTC</span>
                <span className="hidden sm:inline">Filament Coffee Track Club</span>
              </h1>
              <p className="text-xs text-ink-muted">{seasonLabel}</p>
            </div>
          </Link>

          {/* On mobile this row spreads full width (switcher left, nav right);
              from sm up it hugs the right edge next to the logo. */}
          <div className="flex items-center justify-between sm:justify-end gap-2 sm:gap-5">
            {/* Year switcher — a dropdown so "All time" fits alongside the
                individual seasons without crowding the pill row. A native
                <select> keeps it keyboard- and screen-reader-friendly; we just
                restyle the chrome (custom chevron, rounded border) to match. */}
            <div className="relative">
              <select
                value={String(selectedYear)}
                onChange={(e) => selectYear(e.target.value)}
                aria-label="Select season"
                className="appearance-none rounded-full border border-border bg-card pl-3 pr-8 py-1 text-sm font-medium tabular-nums text-ink hover:border-ink-muted focus:outline-none focus:ring-2 focus:ring-accent cursor-pointer"
              >
                {YEAR_OPTIONS.map((opt) => (
                  <option key={String(opt.value)} value={String(opt.value)}>
                    {opt.label}
                  </option>
                ))}
              </select>
              {/* Chevron, pointer-events-none so clicks fall through to the select. */}
              <svg
                className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-ink-muted"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                aria-hidden="true"
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </svg>
            </div>

            {/* Nav */}
            <nav className="flex items-center gap-1 sm:gap-2">
              <Link
                to={`/?year=${selectedYear}`}
                className={`px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap transition-colors ${
                  !isWrapped
                    ? 'bg-accent text-card'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                Dashboard
              </Link>
              <Link
                to="/2025wrapped"
                className={`px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap transition-colors ${
                  isWrapped
                    ? 'bg-accent text-card'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                2025 Wrapped
              </Link>
            </nav>
          </div>
        </div>
      </div>
    </header>
  )
}
