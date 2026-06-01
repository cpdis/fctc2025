// Shared Recharts defaults for the clean dashboard.
//
// The goal is a high data-ink ratio: no axis lines, no tick lines, no full grid,
// muted labels, and a quiet tooltip. These are theme-aware: in a dark scheme the
// surfaces and ink flip, so the chart chrome (axis text, grid, tooltip, series)
// must follow. Get them via the useChartTheme() hook, which reads the current
// scheme, then spread onto the matching Recharts components:
//
//   const ct = useChartTheme()
//   <XAxis dataKey="x" {...ct.axisProps} />
//   <CartesianGrid {...ct.gridProps} />
//   <Tooltip contentStyle={ct.tooltipContentStyle} ... />
//   <Line stroke={ct.palette[0]} ... />
//
import { dashboardColors, dataColors, dataColorMuted } from './theme'
import { useThemeColors } from './useThemeColors'

/**
 * Build the full set of Recharts style objects for a given resolved palette.
 *
 * @param {typeof dashboardColors} colors  surface/ink colors for the scheme
 * @param {string[]} data                  ordered data palette for the scheme
 * @param {string} dataMuted               muted context color for the scheme
 */
export function makeChartTheme(colors, data, dataMuted) {
  const tickStyle = {
    fontSize: 11,
    fill: colors.inkMuted,
    fontFamily: 'var(--font-sans)',
  }

  return {
    palette: data,
    mutedColor: dataMuted,

    // Axis props: strip the chartjunk. No axis line, no tick marks, small muted
    // text. Works for both <XAxis> and <YAxis>.
    axisProps: {
      axisLine: false,
      tickLine: false,
      tick: tickStyle,
      tickMargin: 8,
    },

    // Minimal grid: a single set of horizontal dotted guides at low opacity.
    gridProps: {
      vertical: false,
      horizontal: true,
      stroke: colors.border,
      strokeDasharray: '2 4',
      strokeOpacity: 0.6,
    },

    // Quiet tooltip: card surface, hairline border, soft shadow.
    tooltipContentStyle: {
      background: colors.card,
      border: `1px solid ${colors.border}`,
      borderRadius: 12,
      boxShadow: '0 2px 8px rgba(0, 0, 0, 0.12)',
      padding: '8px 12px',
      fontSize: 12,
      fontFamily: 'var(--font-sans)',
      color: colors.ink,
    },
    tooltipLabelStyle: {
      color: colors.inkMuted,
      fontSize: 11,
      marginBottom: 4,
    },
    tooltipItemStyle: {
      color: colors.ink,
      padding: 0,
    },
    tooltipCursor: {
      stroke: colors.border,
      strokeWidth: 1,
    },

    chartMargin: { top: 12, right: 16, bottom: 8, left: 8 },

    lineProps: {
      stroke: data[0],
      strokeWidth: 2,
      dot: false,
      activeDot: { r: 4, fill: data[0] },
    },
  }
}

/**
 * Hook: the chart theme for the current color scheme. Recomputes (and re-renders
 * the chart) when the OS scheme changes.
 */
export function useChartTheme() {
  const { colors, data, dataMuted } = useThemeColors()
  return makeChartTheme(colors, data, dataMuted)
}

// ── Static light-scheme exports ──────────────────────────────────────────────
// Retained for any caller that doesn't (or can't) use the hook. These are the
// light values only; prefer useChartTheme() for anything that must follow dark.
const lightTheme = makeChartTheme(dashboardColors, dataColors, dataColorMuted)
export const palette = lightTheme.palette
export const mutedColor = lightTheme.mutedColor
export const axisProps = lightTheme.axisProps
export const gridProps = lightTheme.gridProps
export const tooltipContentStyle = lightTheme.tooltipContentStyle
export const tooltipLabelStyle = lightTheme.tooltipLabelStyle
export const tooltipItemStyle = lightTheme.tooltipItemStyle
export const tooltipCursor = lightTheme.tooltipCursor
export const chartMargin = lightTheme.chartMargin
export const lineProps = lightTheme.lineProps
