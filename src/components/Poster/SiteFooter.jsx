/**
 * The dark footer band: the club and the view on the left, the motto on the
 * right.
 *
 * @param {{ seasonLabel: string }} props - "2026 Season" or "All Time"
 */
export default function SiteFooter({ seasonLabel }) {
  return (
    <footer className="site-foot">
      <div className="wrap mono">
        <span>Filament Coffee Track Club · {seasonLabel}</span>
        <span>Keep running, keep caffeinating</span>
      </div>
    </footer>
  )
}
