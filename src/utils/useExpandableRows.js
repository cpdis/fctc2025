import { useEffect, useState } from 'react'

/**
 * Collapse a long list to `initial` rows with a Show more / Show fewer toggle.
 *
 * Returns the slice to render plus the toggle state. Collapses back to `initial`
 * whenever `resetKey` changes (e.g. the selected year or the active filter set),
 * so an expansion from one dataset never carries over to another.
 *
 * @param {Array} rows         the full (already sorted/filtered) list
 * @param {number} initial     rows shown while collapsed (default 15)
 * @param {*} resetKey         identity that, when changed, re-collapses the list
 * @returns {{ visible: Array, expanded: boolean, canExpand: boolean,
 *             hiddenCount: number, total: number, toggle: () => void }}
 */
export function useExpandableRows(rows, initial = 15, resetKey) {
  const list = Array.isArray(rows) ? rows : []
  const [expanded, setExpanded] = useState(false)

  // Re-collapse when the underlying dataset changes (year switch, filter change).
  useEffect(() => {
    setExpanded(false)
  }, [resetKey])

  const total = list.length
  const canExpand = total > initial
  const visible = expanded || !canExpand ? list : list.slice(0, initial)

  return {
    visible,
    expanded,
    canExpand,
    hiddenCount: Math.max(0, total - initial),
    total,
    toggle: () => setExpanded((e) => !e),
  }
}
