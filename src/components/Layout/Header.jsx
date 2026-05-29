import { Link, useLocation, useSearchParams } from 'react-router-dom'
import { YEAR_LIST, LATEST_YEAR, resolveYear } from '../../config/years'

// Clean, minimal dashboard header.
//
// Layout: logo + club name on the left, nav (Dashboard | 2025 Wrapped) and the
// year switcher on the right. The switcher is a segmented pill group that writes
// the selected year into the URL (?year=YYYY); App.jsx reads it back via
// useSearchParams. Active controls use the single dark ink accent, everything
// else is muted grey on a white surface.
export default function Header() {
  const location = useLocation()
  const isWrapped = location.pathname.startsWith('/wrapped') ||
    location.pathname.startsWith('/2025wrapped')

  // Read the current year from the URL (defaults to the latest valid year).
  const [searchParams, setSearchParams] = useSearchParams()
  const selectedYear = resolveYear(searchParams.get('year'))

  // Set ?year while preserving any other query params already in the URL.
  const selectYear = (year) => {
    const next = new URLSearchParams(searchParams)
    next.set('year', String(year))
    setSearchParams(next)
  }

  return (
    <header className="sticky top-0 z-50 bg-card border-b border-border">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
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
              <p className="text-xs text-ink-muted">{selectedYear} Season</p>
            </div>
          </Link>

          {/* On mobile this row spreads full width (switcher left, nav right);
              from sm up it hugs the right edge next to the logo. */}
          <div className="flex items-center justify-between sm:justify-end gap-2 sm:gap-5">
            {/* Year switcher */}
            <div className="flex items-center rounded-full border border-border p-0.5">
              {YEAR_LIST.map((year) => {
                const active = year === selectedYear
                return (
                  <button
                    key={year}
                    onClick={() => selectYear(year)}
                    aria-pressed={active}
                    className={`px-3 py-1 rounded-full text-sm font-medium tabular-nums transition-colors ${
                      active
                        ? 'bg-accent text-card'
                        : 'text-ink-muted hover:text-ink'
                    }`}
                  >
                    {year}
                  </button>
                )
              })}
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
