import { useLayoutEffect, useState } from 'react'

// Small pieces every hand-rolled Poster chart shares (KTD8): the measured
// width they draw to, the run wording their tooltips use, and the arrow-key
// step for their single roving tab stop.

/**
 * The content width of an element, kept current as it resizes. It reads null
 * until the first measure, so a chart can wait to draw rather than draw twice.
 * The measure runs in a layout effect, before paint, so nothing flashes.
 * jsdom has no layout (width 0), so tests draw at `fallback`.
 *
 * @param {{ current: HTMLElement|null }} ref - the element to measure; it
 *   must be mounted with the component that calls this hook
 * @param {number} fallback - the width to use when the element reports 0
 * @returns {number|null}
 */
export function useWidth(ref, fallback) {
  const [width, setWidth] = useState(null)
  useLayoutEffect(() => {
    const element = ref.current
    const measure = () => setWidth(element.clientWidth || fallback)
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(element)
    return () => observer.disconnect()
  }, [ref, fallback])
  return width
}

// Text advance per character as a share of the font size, to keep SVG labels
// inside their chart without measuring them: Space Mono is exactly 0.6em;
// Anton caps and digits run a little under 0.55em.
export const MONO_ADVANCE = 0.6
export const ANTON_ADVANCE = 0.55

/**
 * Where a direct label goes beside a point: to its right, or anchored to its
 * left when it would run past the chart's edge.
 *
 *   fits:     •  LABEL TEXT          (start at px + gap)
 *   flipped:     LABEL TEXT  •|      (end at px − gap)
 *
 * A negative gap starts the label just left of the point, as a flag over it.
 *
 * @param {number} px - the point's x
 * @param {string} text - the label, as drawn
 * @param {number} fontSize - px
 * @param {number} advance - MONO_ADVANCE or ANTON_ADVANCE
 * @param {number} width - the chart's width
 * @param {number} [gap] - px between the point and the label
 * @returns {{ x: number, anchor: 'start'|'end', flipped: boolean }}
 */
export function fitLabel(px, text, fontSize, advance, width, gap = 10) {
  const fits = px + gap + text.length * fontSize * advance <= width
  return fits ? { x: px + gap, anchor: 'start', flipped: false } : { x: px - gap, anchor: 'end', flipped: true }
}

/** "Half Marathon · Invasion Day", or just "Intervals" when the run has no event. */
export function runName(run) {
  return run.event ? `${run.type} · ${run.event}` : run.type
}

/** "8.0 km", or "—" for a run with attendance but no recorded distance. */
export function kmText(km) {
  return km > 0 ? `${km.toFixed(1)} km` : '—'
}

/**
 * Where an arrow key moves a roving tab stop along one axis. Charts keep one
 * mark tabbable (tabIndex 0) and move it with the arrows, so a keyboard user
 * tabs past a chart in one step instead of through every mark.
 *
 * @param {string} key - KeyboardEvent.key
 * @param {number} index - the current position
 * @param {number} count - positions on the axis
 * @param {{ back: string, forward: string }} [keys] - the axis's arrow keys
 * @returns {number|null} the new position, or null when the key is not a move
 */
export function rovingStep(key, index, count, keys = { back: 'ArrowLeft', forward: 'ArrowRight' }) {
  const last = count - 1
  switch (key) {
    case keys.back:
      return Math.max(0, index - 1)
    case keys.forward:
      return Math.min(last, index + 1)
    case 'Home':
      return 0
    case 'End':
      return last
    default:
      return null
  }
}
