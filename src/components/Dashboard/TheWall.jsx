import { memo, useCallback, useId, useLayoutEffect, useMemo, useRef, useState } from 'react'
import Tooltip, { useTooltip } from '../Poster/Tooltip'
import { formatDay, monthName } from '../Poster/format'
import { kmText, rovingStep, runName, useWidth } from './chartKit'
import { compareNames } from '../../utils/dashboardMetrics'

// Geometry in px, from the approved mockup: rows 18 apart with 12-high cells
// under a 30px header (month labels, special diamonds), columns at least 7
// wide. A season fills the width on a desktop and scrolls sideways on a phone.
const ROW = 18
const TOP = 30
const CELL_H = 12
const MIN_COL = 7
const FALLBACK_WIDTH = 800

// "Find yourself" survives reloads and year switches (KTD9).
const STORAGE_KEY = 'fctc.findYourself'

const byName = (a, b) => compareNames(a.name, b.name)

// The sort select. Ties fall back to runs, then A–Z, so the order is stable.
const SORTS = {
  runs: { label: 'Sort: most runs', compare: (a, b) => b.runs - a.runs || byName(a, b) },
  streak: { label: 'Sort: current streak', compare: (a, b) => b.current - a.current || b.runs - a.runs || byName(a, b) },
  name: { label: 'Sort: A–Z', compare: byName },
}

const UP_DOWN = { back: 'ArrowUp', forward: 'ArrowDown' }

// Storage can throw (private mode, blocked site data); the choice then lasts
// only for this visit.
function readChoice() {
  try {
    return localStorage.getItem(STORAGE_KEY) ?? ''
  } catch {
    return ''
  }
}

function writeChoice(name) {
  try {
    if (name) localStorage.setItem(STORAGE_KEY, name)
    else localStorage.removeItem(STORAGE_KEY)
  } catch {
    // Not saved; the selection still applies until the page closes.
  }
}

/** A cell's state in words, for its tooltip and its accessible name. */
function cellStatus(cell) {
  if (cell.notOnRoster) return 'not on the roster'
  if (!cell.ran) return 'missed'
  return cell.streak ? 'ran ✓ (current streak)' : 'ran ✓'
}

/** CSS class for a cell's fill (poster-charts.css). */
function cellClass(cell) {
  if (cell.notOnRoster) return 'cell off'
  if (!cell.ran) return 'cell'
  return cell.streak ? 'cell ran streak' : 'cell ran'
}

/**
 * The Wall (R11, R12): every active runner against every run of the view.
 * Names on the left and totals (runs, current streak) on the right are plain
 * HTML, so the grid reads without hover; the SVG grid between them scrolls
 * sideways when the season is wider than the screen.
 *
 * Above it: a "Find yourself…" select (the view's active runners A–Z) that
 * highlights one row and dims the rest, and a sort select. The chosen runner
 * persists in localStorage and comes back in any view where they ran.
 *
 * @param {{ model: ReturnType<typeof import('../../utils/dashboardMetrics').wallModel> }} props
 */
export default function TheWall({ model }) {
  const headingId = useId()
  const [sort, setSort] = useState('runs')
  const [chosen, setChosen] = useState(readChoice)

  const rows = useMemo(() => [...model.rows].sort(SORTS[sort].compare), [model.rows, sort])
  const runners = useMemo(() => model.rows.map((row) => row.name).sort(compareNames), [model.rows])
  const offRoster = useMemo(() => model.rows.some((row) => row.cells.some((cell) => cell.notOnRoster)), [model.rows])

  // The stored runner shows only in a view where they ran; the choice itself
  // is kept, so switching back to such a view finds them again.
  const selected = runners.includes(chosen) ? chosen : ''
  const choose = (name) => {
    setChosen(name)
    writeChoice(name)
  }

  return (
    <section className="block" aria-labelledby={headingId}>
      <div className="kick">
        <h2 id={headingId} className="display">
          The Wall
        </h2>
        <p className="mono">Every runner, every run</p>
      </div>

      {model.columns.length === 0 ? (
        <p className="soft">No runs yet.</p>
      ) : (
        <>
          <div className="wall-tools">
            <select className="pick" aria-label="Find a runner" value={selected} onChange={(e) => choose(e.target.value)}>
              <option value="">Find yourself…</option>
              {runners.map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))}
            </select>
            <select className="pick" aria-label="Sort runners" value={sort} onChange={(e) => setSort(e.target.value)}>
              {Object.entries(SORTS).map(([key, { label }]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ))}
            </select>
            <div className="legend">
              <span>
                <i className="sw-ran" />
                Ran
              </span>
              <span>
                <i className="sw-streak" />
                Current streak
              </span>
              <span>
                <i className="sw-special" />
                Special (not a club day)
              </span>
              {offRoster && (
                <span>
                  <i className="sw-off" />
                  Not on the roster
                </span>
              )}
            </div>
          </div>
          <WallGrid rows={rows} columns={model.columns} selected={selected} />
        </>
      )}
    </section>
  )
}

/**
 * The names column, the scrolling SVG grid and the totals column, plus the
 * grid's tooltip, keyboard focus and first-load motion.
 */
function WallGrid({ rows, columns, selected }) {
  const gridRef = useRef(null)
  const svgRef = useRef(null)
  const width = useWidth(gridRef, FALLBACK_WIDTH)
  const { tip, show, hide } = useTooltip()
  // The one tabbable cell (roving tab stop). c -1 is the latest run.
  const [active, setActive] = useState({ r: 0, c: -1 })
  // The print-in sweep runs once, on the first draw (poster-charts.css).
  const [printing, setPrinting] = useState(true)

  const lastCol = columns.length - 1
  const colW = Math.max(MIN_COL, (width ?? 0) / columns.length)
  const ar = Math.max(0, Math.min(active.r, rows.length - 1))
  const ac = active.c < 0 ? lastCol : Math.min(active.c, lastCol)

  // Open on the latest runs: on the first draw and on a year switch (a new
  // set of columns), never on a sort, a find or a resize.
  const scrolledFor = useRef(null)
  useLayoutEffect(() => {
    if (width === null || scrolledFor.current === columns) return
    scrolledFor.current = columns
    gridRef.current.scrollLeft = gridRef.current.scrollWidth
  }, [width, columns])

  // Per column: "Fri 25 Sep, River Loop" for cell names, and the delay step
  // of the print-in sweep, shared by every cell in the column.
  const columnLabels = useMemo(() => columns.map(({ run }) => `${formatDay(run.parsedDate)}, ${runName(run)}`), [columns])
  const columnStyles = useMemo(() => columns.map((_, c) => ({ '--c': c })), [columns])
  const months = useMemo(() => monthMarks(columns), [columns])

  // The same detail for a hovered and a focused cell. Without a row (the
  // header band) it describes the run alone.
  const tipFor = useCallback(
    (c, r) => {
      const { run, special } = columns[c]
      const row = rows[r]
      return (
        <>
          <b>{formatDay(run.parsedDate)}</b> · {run.location}
          <br />
          {runName(run)} · {kmText(run.actualKm)} · {run.totalAttendance} runners
          {special && (
            <>
              <br />
              Special: not a club day
            </>
          )}
          {row && (
            <>
              <br />
              {row.name}: {cellStatus(row.cells[c])}
            </>
          )}
        </>
      )
    },
    [columns, rows]
  )

  // One pointer handler for the whole grid, by position, so hovering the gaps
  // between cells or the header band still reads the column.
  const onMouseMove = (event) => {
    const box = event.currentTarget.getBoundingClientRect()
    const c = Math.floor((event.clientX - box.left) / colW)
    const r = Math.floor((event.clientY - box.top - TOP) / ROW)
    if (c < 0 || c > lastCol) hide()
    else show(tipFor(c, r), event)
  }

  const onCellFocus = useCallback(
    (event) => {
      const r = Number(event.currentTarget.dataset.r)
      const c = Number(event.currentTarget.dataset.c)
      setActive((current) => (current.r === r && current.c === c ? current : { r, c }))
      show(tipFor(c, r), event)
    },
    [show, tipFor]
  )

  // Arrows move the tab stop cell by cell; Home and End jump along the row.
  const onKeyDown = (event) => {
    const vertical = event.key === 'ArrowUp' || event.key === 'ArrowDown'
    const r = vertical ? rovingStep(event.key, ar, rows.length, UP_DOWN) : ar
    const c = vertical ? ac : rovingStep(event.key, ac, columns.length)
    if (r === null || c === null) return
    event.preventDefault()
    setActive({ r, c })
    svgRef.current.querySelector(`[data-r="${r}"][data-c="${c}"]`)?.focus()
  }

  const dim = (name) => Boolean(selected) && selected !== name
  const height = TOP + rows.length * ROW + 6

  return (
    <>
      <div className="wall">
        {/* Hidden from assistive tech: each grid row carries the same name and totals. */}
        <div className="names" aria-hidden="true">
          {rows.map(({ name }) => (
            <div key={name} className={dim(name) ? 'dim' : name === selected ? 'hl' : undefined}>
              {name}
            </div>
          ))}
        </div>
        <div className="grid" ref={gridRef}>
          {width !== null && (
            <svg
              ref={svgRef}
              className={printing ? 'print' : undefined}
              width={colW * columns.length}
              height={height}
              role="grid"
              aria-label="Attendance grid: one row per runner, one column per run"
              onMouseMove={onMouseMove}
              onMouseLeave={hide}
              onBlur={hide}
              onKeyDown={onKeyDown}
              onAnimationEnd={(event) => {
                // Every cell in the last column ends together: the sweep is done.
                if (event.target.dataset?.c === String(lastCol)) setPrinting(false)
              }}
            >
              <g aria-hidden="true">
                {columns.map(
                  ({ special }, c) =>
                    special && (
                      <g key={c}>
                        <rect className="band" x={c * colW} y={TOP - 8} width={colW} height={rows.length * ROW + 8} />
                        <path className="diamond" d={`M${c * colW + colW / 2} ${TOP - 10} l3 4 l-3 4 l-3 -4z`} />
                      </g>
                    )
                )}
                {months.map(({ c, label }) => (
                  <g key={c}>
                    <line className="month-line" x1={c * colW} x2={c * colW} y1={4} y2={TOP + rows.length * ROW} />
                    <text className="month" x={c * colW + 3} y={14}>
                      {label}
                    </text>
                  </g>
                ))}
              </g>
              <WallRows
                rows={rows}
                colW={colW}
                dimmed={selected}
                ar={ar}
                ac={ac}
                columnLabels={columnLabels}
                columnStyles={columnStyles}
                onCellFocus={onCellFocus}
              />
            </svg>
          )}
        </div>
        <div className="tots" aria-hidden="true">
          {rows.map(({ name, runs, current }) => (
            <div key={name} className={dim(name) ? 'dim' : undefined}>
              {runs} · {current ? <span className="up">{current}▲</span> : '–'}
            </div>
          ))}
        </div>
      </div>
      {/* Outside the scroller, so the fixed tip is never clipped by it. */}
      <Tooltip tip={tip} />
    </>
  )
}

/**
 * The grid's rows of cells: the bulk of the DOM (runners × runs rects). Memoized
 * so moving the tooltip, which re-renders WallGrid, never re-renders them.
 */
const WallRows = memo(function WallRows({ rows, colW, dimmed, ar, ac, columnLabels, columnStyles, onCellFocus }) {
  const cellW = Math.max(3, colW - 2)
  return rows.map((row, r) => (
    <g
      key={row.name}
      role="row"
      aria-label={`${row.name}: ${row.runs} runs, current streak ${row.current}`}
      className={dimmed && dimmed !== row.name ? 'dim' : undefined}
    >
      {row.cells.map((cell, c) => (
        <rect
          key={c}
          role="gridcell"
          className={cellClass(cell)}
          x={c * colW + 1}
          y={TOP + r * ROW + (ROW - CELL_H) / 2}
          width={cellW}
          height={CELL_H}
          style={columnStyles[c]}
          tabIndex={r === ar && c === ac ? 0 : -1}
          data-r={r}
          data-c={c}
          aria-label={`${columnLabels[c]}: ${row.name} ${cellStatus(cell)}`}
          onFocus={onCellFocus}
        />
      ))}
    </g>
  ))
})

/**
 * Where each month starts along the columns, labelled "SEP". A view that spans
 * seasons (All time) adds the year to its first column and every January,
 * "JAN ’26", so the two Septembers read apart.
 */
function monthMarks(columns) {
  const years = new Set(columns.map(({ date }) => date.slice(0, 4)))
  const marks = []
  let previous = null
  columns.forEach(({ date }, c) => {
    const key = date.slice(0, 7)
    if (key === previous) return
    previous = key
    const month = Number(date.slice(5, 7)) - 1
    const name = monthName(month).toUpperCase()
    const withYear = years.size > 1 && (month === 0 || c === 0)
    marks.push({ c, label: withYear ? `${name} ’${date.slice(2, 4)}` : name })
  })
  return marks
}
