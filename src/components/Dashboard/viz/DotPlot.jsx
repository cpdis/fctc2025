import { dashboardColors, dataColors } from '../../../utils/theme'

/**
 * DotPlot — Cleveland dot plot. One horizontal row per item with a single dot
 * positioned by value. Cleaner and easier to read than a bar chart: no heavy
 * ink, just a label, a faint baseline, and a dot.
 *
 * Props:
 *   data       Array<{ label, value }>  — one entry per row
 *   width      number   — viewBox width (default 320)
 *   rowHeight  number   — vertical space per row (default 28)
 *   max        number   — value at the right edge (default: max of data)
 *   color      string   — dot color (default accent)
 *   format     (n)=>string — value formatter (default identity)
 *   labelWidth number   — px reserved for labels on the left (default 90)
 *   ariaLabel  string   — accessible label
 */
export default function DotPlot({
  data = [],
  width = 320,
  rowHeight = 28,
  max,
  color = dataColors[1],
  format = (n) => String(n),
  labelWidth = 90,
  ariaLabel = 'Dot plot',
}) {
  const rows = Array.isArray(data) ? data : []
  const padTop = 8
  const padBottom = 8
  const height = padTop + padBottom + rows.length * rowHeight

  const trackStart = labelWidth
  const trackEnd = width - 36 // leave room for the value printed at the dot
  const trackW = Math.max(1, trackEnd - trackStart)

  const dataMax = rows.length ? Math.max(...rows.map((d) => d.value)) : 0
  const scaleMax = (max ?? dataMax) || 1 // avoid divide-by-zero

  const xFor = (v) => trackStart + (v / scaleMax) * trackW
  const yFor = (i) => padTop + i * rowHeight + rowHeight / 2

  return (
    <svg
      role="img"
      aria-label={ariaLabel}
      viewBox={`0 0 ${width} ${height}`}
      width="100%"
      height="auto"
      style={{ display: 'block', fontFamily: 'var(--font-sans)' }}
    >
      <title>{ariaLabel}</title>

      {rows.map((d, i) => {
        const y = yFor(i)
        const cx = xFor(d.value)
        return (
          <g key={d.label ?? i}>
            {/* Faint baseline from label to the dot for the eye to ride along */}
            <line
              data-testid="dot-track"
              x1={trackStart}
              y1={y}
              x2={cx}
              y2={y}
              stroke={dashboardColors.border}
              strokeWidth={1}
            />
            <text
              x={trackStart - 8}
              y={y}
              textAnchor="end"
              dominantBaseline="middle"
              fontSize="11"
              fill={dashboardColors.inkMuted}
            >
              {d.label}
            </text>
            <circle
              data-testid="dot-plot-dot"
              cx={cx}
              cy={y}
              r={4}
              fill={color}
            />
            <text
              x={cx + 8}
              y={y}
              textAnchor="start"
              dominantBaseline="middle"
              fontSize="11"
              fill={dashboardColors.ink}
            >
              {format(d.value)}
            </text>
          </g>
        )
      })}
    </svg>
  )
}
