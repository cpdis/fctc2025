import { useCallback, useState } from 'react'

// Offsets from the anchor point and the tip's widest box (max-width 280px in
// poster.css plus a margin), so it never runs off the right edge.
const OFFSET_X = 14
const OFFSET_Y = 16
const TIP_ROOM = 300

const CLOSED = { open: false, content: null, left: 0, top: 0 }

/**
 * Where the tip sits for an event. Mouse events place it beside the pointer.
 * Focus events carry no pointer, so the tip sits under the focused mark: the
 * same detail for keyboard users as for hover.
 *
 * @param {MouseEvent|FocusEvent|import('react').SyntheticEvent} event
 * @param {number} viewportWidth
 * @returns {{ left: number, top: number }} viewport (fixed) coordinates
 */
export function tipPosition(event, viewportWidth) {
  let x = event.clientX
  let y = event.clientY
  if (typeof x !== 'number') {
    const box = event.currentTarget.getBoundingClientRect()
    x = box.left + box.width / 2
    y = box.bottom
  }
  return { left: Math.max(0, Math.min(x + OFFSET_X, viewportWidth - TIP_ROOM)), top: y + OFFSET_Y }
}

/**
 * State for one shared chart tooltip. Wire `show` to a mark's onMouseMove and
 * onFocus, `hide` to onMouseLeave and onBlur, and render <Tooltip tip={tip} />.
 * Hiding keeps the last content so the fade-out does not blank the box.
 *
 * @returns {{ tip: object, show: (content: import('react').ReactNode, event: object) => void, hide: () => void }}
 */
export function useTooltip() {
  const [tip, setTip] = useState(CLOSED)
  const show = useCallback((content, event) => {
    setTip({ open: true, content, ...tipPosition(event, window.innerWidth) })
  }, [])
  const hide = useCallback(() => setTip((current) => ({ ...current, open: false })), [])
  return { tip, show, hide }
}

/**
 * The tooltip box: espresso with crema text, gold for <b>, fixed to the
 * viewport. Render it inside the .poster root (for the tokens) and outside any
 * transformed ancestor, which would re-anchor `position: fixed`.
 *
 * @param {{ tip: ReturnType<typeof useTooltip>['tip'] }} props
 */
export default function Tooltip({ tip }) {
  return (
    <div
      className="tip"
      role="tooltip"
      aria-hidden={!tip.open}
      data-open={tip.open || undefined}
      style={{ left: tip.left, top: tip.top }}
    >
      {tip.content}
    </div>
  )
}
