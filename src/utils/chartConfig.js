// Shared Recharts defaults for the clean dashboard.
//
// The goal is a high data-ink ratio: no axis lines, no tick lines, no full grid,
// muted labels, and a quiet tooltip. Spread these objects onto the matching
// Recharts components so every chart looks identical without copy-pasting props.
//
//   <XAxis dataKey="x" {...axisProps} />
//   <YAxis {...axisProps} />
//   <CartesianGrid {...gridProps} />
//   <Tooltip contentStyle={tooltipContentStyle} ... />
//
import { dashboardColors, dataColors, dataColorMuted } from './theme'

// Re-export the palette so chart code has a single import for colors.
export const palette = dataColors
export const mutedColor = dataColorMuted

// Muted tick label styling shared by both axes.
const tickStyle = {
  fontSize: 11,
  fill: dashboardColors.inkMuted,
  fontFamily: 'var(--font-sans)',
}

// Axis props: strip the chartjunk. No axis line, no tick marks, small muted text.
// Works for both <XAxis> and <YAxis>.
export const axisProps = {
  axisLine: false,
  tickLine: false,
  tick: tickStyle,
  // Pull labels in a touch so they sit closer to the data.
  tickMargin: 8,
}

// Minimal grid: a single set of horizontal dotted guides at low opacity.
// Hide the vertical lines entirely (vertical={false}) to keep it Tufte-quiet.
export const gridProps = {
  vertical: false,
  horizontal: true,
  stroke: dashboardColors.border,
  strokeDasharray: '2 4',
  strokeOpacity: 0.6,
}

// Quiet tooltip: white card, hairline border, soft shadow, no default chartjunk.
export const tooltipContentStyle = {
  background: dashboardColors.card,
  border: `1px solid ${dashboardColors.border}`,
  borderRadius: 12,
  boxShadow: '0 2px 8px rgba(26, 26, 24, 0.08)',
  padding: '8px 12px',
  fontSize: 12,
  fontFamily: 'var(--font-sans)',
  color: dashboardColors.ink,
}

export const tooltipLabelStyle = {
  color: dashboardColors.inkMuted,
  fontSize: 11,
  marginBottom: 4,
}

export const tooltipItemStyle = {
  color: dashboardColors.ink,
  padding: 0,
}

// Cursor styling (the vertical/horizontal hover line). Keep it a faint hairline.
export const tooltipCursor = {
  stroke: dashboardColors.border,
  strokeWidth: 1,
}

// Sensible default chart margins so labels never clip.
export const chartMargin = { top: 12, right: 16, bottom: 8, left: 8 }

// Default line styling for the primary series.
export const lineProps = {
  stroke: dataColors[0],
  strokeWidth: 2,
  dot: false,
  activeDot: { r: 4, fill: dataColors[0] },
}
