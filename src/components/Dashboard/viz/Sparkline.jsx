import { dashboardColors } from '../../../utils/theme'

/**
 * Sparkline — a tiny, word-sized SVG line chart with no axes or labels.
 *
 * Dependency-free and responsive: the SVG fills its container width while the
 * internal coordinate space stays fixed via viewBox. Intended to sit inline
 * next to a number (Tufte's "data-words").
 *
 * Props:
 *   data       number[]  — the series to plot (left → right)
 *   width      number    — viewBox width (default 120)
 *   height     number    — viewBox height (default 28)
 *   color      string    — stroke color (default ink)
 *   strokeWidth number   — line weight (default 1.5)
 *   lastDot    boolean   — draw a dot on the final point (default true)
 *   ariaLabel  string    — accessible label
 */
export default function Sparkline({
  data = [],
  width = 120,
  height = 28,
  color = dashboardColors.ink,
  strokeWidth = 1.5,
  lastDot = true,
  ariaLabel = 'Sparkline',
}) {
  const pad = strokeWidth + 1 // keep the stroke + dot from clipping at the edges
  const innerW = width - pad * 2
  const innerH = height - pad * 2

  // Need at least one point to draw anything meaningful.
  const hasData = Array.isArray(data) && data.length > 0
  const min = hasData ? Math.min(...data) : 0
  const max = hasData ? Math.max(...data) : 0
  const range = max - min || 1 // avoid divide-by-zero when all values are equal

  // Map a value index → x, value → y (SVG y grows downward, so invert).
  const xFor = (i) =>
    data.length > 1 ? pad + (i / (data.length - 1)) * innerW : pad + innerW / 2
  const yFor = (v) => pad + innerH - ((v - min) / range) * innerH

  const points = hasData ? data.map((v, i) => [xFor(i), yFor(v)]) : []
  const pointsAttr = points.map(([x, y]) => `${x},${y}`).join(' ')
  const last = points[points.length - 1]

  return (
    <svg
      role="img"
      aria-label={ariaLabel}
      viewBox={`0 0 ${width} ${height}`}
      width="100%"
      height={height}
      preserveAspectRatio="none"
      style={{ display: 'block', overflow: 'visible' }}
    >
      <title>{ariaLabel}</title>
      {points.length > 1 && (
        <polyline
          data-testid="sparkline-line"
          points={pointsAttr}
          fill="none"
          stroke={color}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeLinejoin="round"
          vectorEffect="non-scaling-stroke"
        />
      )}
      {lastDot && last && (
        <circle
          data-testid="sparkline-dot"
          cx={last[0]}
          cy={last[1]}
          r={strokeWidth + 0.5}
          fill={color}
        />
      )}
    </svg>
  )
}
