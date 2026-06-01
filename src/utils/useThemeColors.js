import { useSyncExternalStore } from 'react'
import {
  dashboardColors,
  dataColors,
  dataColorMuted,
  dashboardColorsDark,
  dataColorsDark,
  dataColorMutedDark,
} from './theme'

// Single source of truth for "is the OS/browser asking for dark?". CSS surfaces
// flip via the @media (prefers-color-scheme: dark) block in index.css; the JS
// charts/SVG can't read that media state from their attributes, so they read it
// here and pick concrete hex from the dark palettes in theme.js. Kept in sync
// with that CSS block.
const QUERY = '(prefers-color-scheme: dark)'

function subscribe(callback) {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
    return () => {}
  }
  const mql = window.matchMedia(QUERY)
  mql.addEventListener('change', callback)
  return () => mql.removeEventListener('change', callback)
}

function getSnapshot() {
  return (
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia(QUERY).matches
  )
}

// SSR / no-window fallback: assume light.
function getServerSnapshot() {
  return false
}

/**
 * Reactive boolean: true when the OS/browser prefers a dark color scheme.
 * Re-renders consumers when the preference changes mid-session.
 */
export function usePrefersDark() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot)
}

/**
 * Theme-aware chart/SVG colors. Returns the same shape in both schemes so call
 * sites are scheme-agnostic:
 *   const { colors, data, dataMuted } = useThemeColors()
 *   stroke={data[0]}        // primary series
 *   fill={colors.inkMuted}  // axis label
 *
 * @returns {{ colors: typeof dashboardColors, data: string[], dataMuted: string, isDark: boolean }}
 */
export function useThemeColors() {
  const isDark = usePrefersDark()
  return isDark
    ? { colors: dashboardColorsDark, data: dataColorsDark, dataMuted: dataColorMutedDark, isDark }
    : { colors: dashboardColors, data: dataColors, dataMuted: dataColorMuted, isDark }
}
