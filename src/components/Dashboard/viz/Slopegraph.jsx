import { dashboardColors, dataColors, dataColorMuted } from '../../../utils/theme'

/**
 * Slopegraph — Tufte's two-column before/after chart.
 *
 * Each series is a line connecting its left value to its right value, with the
 * value (and optionally the label) printed directly on the chart. Rising series
 * are colored with the accent; falling/flat series stay muted grey. No axes,
 * no gridlines — the slopes themselves carry the comparison.
 *
 * Props:
 *   data       Array<{ label, left, right }>  — one entry per series
 *   width      number   — viewBox width (default 320)
 *   height     number   — viewBox height (default 240)
 *   leftTitle  string   — header above the left column
 *   rightTitle string   — header above the right column
 *   format     (n)=>string — value formatter (default identity)
 *   ariaLabel  string   — accessible label
 */
export default function Slopegraph({
  data = [],
  width = 320,
  height = 240,
  leftTitle = '',
  rightTitle = '',
  format = (n) => String(n),
  ariaLabel = 'Slopegraph',
}) {
  const padY = 28 // room for column titles up top + breathing room at bottom
  // Push the two columns toward the edges so the slopes have room to read; the
  // label gutters (names left, values right) still fit comfortably.
  const xLeft = width * 0.25
  const xRight = width * 0.75

  const rows = Array.isArray(data) ? data : []

  // Shared value scale across both columns so slopes are comparable.
  const allValues = rows.flatMap((d) => [d.left, d.right])
  const min = allValues.length ? Math.min(...allValues) : 0
  const max = allValues.length ? Math.max(...allValues) : 1
  const range = max - min || 1

  const yFor = (v) =>
    padY + (height - padY * 2) * (1 - (v - min) / range)

  // Labels collide when two series share a value (same y). Dodge the TEXT
  // positions apart to a minimum gap while leaving the dots/lines at their true
  // y. Two passes: push down from the top, then clamp and push back up from the
  // bottom so labels never spill past the plot band.
  const minGap = 13
  const minY = padY
  const maxY = height - padY
  const dodge = (values) => {
    const order = values
      .map((y, i) => ({ y, i }))
      .sort((a, b) => a.y - b.y)
    let prev = -Infinity
    for (const node of order) {
      node.y = Math.max(node.y, prev + minGap)
      prev = node.y
    }
    // Second pass: if we pushed past the bottom, walk back up.
    let next = maxY
    for (let k = order.length - 1; k >= 0; k--) {
      order[k].y = Math.min(order[k].y, next)
      next = order[k].y - minGap
    }
    const out = new Array(values.length)
    for (const node of order) out[node.i] = Math.max(node.y, minY)
    return out
  }

  const leftDotY = rows.map((d) => yFor(d.left))
  const rightDotY = rows.map((d) => yFor(d.right))
  const leftLabelY = dodge(leftDotY)
  const rightLabelY = dodge(rightDotY)

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

      {/* Column headers */}
      {(leftTitle || rightTitle) && (
        <g fontSize="11" fill={dashboardColors.inkMuted}>
          <text x={xLeft} y={14} textAnchor="middle">
            {leftTitle}
          </text>
          <text x={xRight} y={14} textAnchor="middle">
            {rightTitle}
          </text>
        </g>
      )}

      {rows.map((d, i) => {
        const y1 = leftDotY[i]
        const y2 = rightDotY[i]
        const ly1 = leftLabelY[i]
        const ly2 = rightLabelY[i]
        // Rising series get the accent; everything else recedes to grey.
        const color = d.right > d.left ? dataColors[1] : dataColorMuted

        return (
          <g key={d.label ?? i}>
            <line
              data-testid="slope-line"
              x1={xLeft}
              y1={y1}
              x2={xRight}
              y2={y2}
              stroke={color}
              strokeWidth={1.5}
            />
            <circle cx={xLeft} cy={y1} r={2.5} fill={color} />
            <circle cx={xRight} cy={y2} r={2.5} fill={color} />

            {/* Direct labels: name + value on the left, value on the right.
                Labels sit at dodged y positions so ties stay readable. */}
            <text
              x={xLeft - 8}
              y={ly1}
              textAnchor="end"
              dominantBaseline="middle"
              fontSize="11"
              fill={dashboardColors.ink}
            >
              {d.label} {format(d.left)}
            </text>
            <text
              x={xRight + 8}
              y={ly2}
              textAnchor="start"
              dominantBaseline="middle"
              fontSize="11"
              fill={dashboardColors.ink}
            >
              {format(d.right)}
            </text>
          </g>
        )
      })}
    </svg>
  )
}
