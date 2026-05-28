// Shared run-type color assignment so the Run Type Distribution donut and the
// Run History badges agree on which color means which run type.
//
// Color encodes frequency rank, not a fixed per-type hue: the most common type
// gets ink, the next the accent, then a graduated warm-grey ramp. Types beyond
// the top N collapse into the "Special Events" tone (matching the donut, which
// groups them into one slice).

export const DONUT_COLORS = [
  '#15110f', // ink
  '#c1502e', // accent
  '#44403c', // stone-700
  '#78716c', // stone-500
  '#a8a29e', // stone-400
  '#8a3f24', // muted accent
  '#cbc7c2', // stone-300
  '#5f5a55', // stone-600
]

// How many types the donut shows individually before grouping into Special Events.
export const TOP_TYPES_COUNT = 6

// Color for the slice at a given chart index (donut slices, sorted desc by count).
export const sliceColor = (index) => DONUT_COLORS[index % DONUT_COLORS.length]

// Relative luminance of a #rrggbb hex, for picking a readable label color.
export const isLight = (hex) => {
  const n = parseInt(hex.slice(1), 16)
  const r = (n >> 16) & 255
  const g = (n >> 8) & 255
  const b = n & 255
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.6
}

// rgba() string from a hex + alpha, for tinted label backgrounds.
export const tint = (hex, alpha) => {
  const n = parseInt(hex.slice(1), 16)
  const r = (n >> 16) & 255
  const g = (n >> 8) & 255
  const b = n & 255
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

/**
 * Map each raw run type to its color, replicating the donut's assignment:
 * sort by count desc, give the top N distinct tones, collapse the rest to the
 * Special Events tone.
 *
 * @param {Object} runsByType - parser output: { [rawType]: { count, ... } }
 * @returns {Object} { [rawType]: '#hex' }
 */
export function runTypeColorMap(runsByType = {}) {
  const sorted = Object.entries(runsByType)
    .map(([raw, stats]) => ({ raw, value: stats?.count ?? 0 }))
    .sort((a, b) => b.value - a.value)

  const specialColor = DONUT_COLORS[Math.min(TOP_TYPES_COUNT, DONUT_COLORS.length - 1)]
  const map = {}
  sorted.forEach((t, i) => {
    map[t.raw] = i < TOP_TYPES_COUNT ? DONUT_COLORS[i] : specialColor
  })
  return map
}
