import { Link, useLocation } from 'react-router-dom'
import { dashboardBasePath, dashboardHref } from '../../utils/dashboardPaths'

// The hub's origin, for its own pages (home, Cup) when the dashboard is served
// from the app's domain instead of through fctc.fun.
const HUB_ORIGIN = 'https://fctc.fun'

// Hub theme colours for the browser chrome (<meta name="theme-color">).
const CHROME_COLOR = { light: '#faf4e6', dark: '#1c1410' }

/**
 * The fctc.fun site header: cup logo, FCTC with a pink TC, the club apps nav
 * and the theme toggle over a 2px rule, then the sock stripe. The logo, nav
 * and toggle mirror the hub's Base.astro header, so moving between the hub and
 * the dashboard feels like one site.
 *
 * @param {{ year: number|'all' }} props - the selected season, kept on the
 *   Dashboard link so it returns to the same view
 */
export default function SiteHeader({ year }) {
  const base = dashboardBasePath(useLocation().pathname)

  // Hub pages are same-origin paths under the hub, absolute URLs elsewhere.
  const hubHref = (path) => (base ? path : `${HUB_ORIGIN}${path}`)

  return (
    <header className="site-head">
      <div className="bar">
        <a className="mark" href={hubHref('/')}>
          <CupLogo />
          <span>
            FC<b>TC</b>
          </span>
        </a>
        <nav aria-label="Club apps">
          <Link to={dashboardHref(base, year)} aria-current="page">
            Dashboard
          </Link>
          <a href={hubHref('/cup')}>Cup</a>
          {/* Wrapped is this app's own route, at the root and under the hub. */}
          <Link to="/2025wrapped">Wrapped</Link>
          <ThemeToggle />
        </nav>
      </div>
      <div className="stripe" role="presentation" />
    </header>
  )
}

// The hub's cup mark. The two pink steam wisps animate in poster.css.
function CupLogo() {
  return (
    <svg
      className="cup"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      aria-hidden="true"
    >
      <path className="steam s1" d="M9 2.2 q1.1 1.4 0 2.8 q-1.1 1.4 0 2.8" />
      <path className="steam s2" d="M13.5 2.2 q1.1 1.4 0 2.8 q-1.1 1.4 0 2.8" />
      <path d="M5 11 h12 v4.5 a4.5 4.5 0 0 1 -4.5 4.5 h-3 A4.5 4.5 0 0 1 5 15.5 z" />
      <path d="M17 12 h1.2 a2.4 2.4 0 0 1 0 4.8 H17" />
    </svg>
  )
}

/**
 * One theme across fctc.fun: flip `data-theme` on <html> and save the choice
 * in `localStorage.theme`, the same key the hub reads. The icon (sun or moon)
 * follows `data-theme` in CSS, so the button keeps no React state.
 */
function ThemeToggle() {
  const toggle = () => {
    const root = document.documentElement
    const next = root.dataset.theme === 'dark' ? 'light' : 'dark'
    root.dataset.theme = next
    try {
      localStorage.setItem('theme', next)
    } catch {
      // Storage can throw (Safari private mode, blocked site data). The theme
      // still flips for this visit; the next one follows the OS preference.
    }
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', CHROME_COLOR[next])
  }

  return (
    <button type="button" className="theme-toggle" aria-label="Toggle light/dark theme" onClick={toggle}>
      <span className="sun" aria-hidden="true">
        ☀
      </span>
      <span className="moon" aria-hidden="true">
        ☾
      </span>
    </button>
  )
}
