import { memo, useCallback, useId, useMemo, useRef, useState } from 'react'
import Tooltip, { useTooltip } from '../Poster/Tooltip'
import { formatDay, formatNumber, parseIsoDate } from '../Poster/format'
import { MONO_ADVANCE, fitLabel, rovingStep, runName, useWidth } from './chartKit'
import { WEEKDAY_NAMES } from '../../utils/clubDays'

// Dot geometry in px, from the approved mockup: 5px dots stacked 1.4px apart,
// columns 12px wide for the pointer, 12px of inset at each end of the scale,
// 26px of headroom over the tallest column for the busiest day's label.
const DOT = 5
const GAP = 1.4
const HIT = 12
const INSET = 12
const HEADROOM = 26
const LABEL_SIZE = 11
const FALLBACK_WIDTH = 900
const DAY_MS = 86_400_000

/** "Monday", or "Specials" for the weekend and holiday track. */
const fullName = (track) => WEEKDAY_NAMES[track.name] ?? track.name

/** The same words for a hovered and a focused column. */
function columnTip(column) {
  return (
    <>
      <b>{formatDay(parseIsoDate(column.date))}</b>
      <br />
      {column.runs.map(runName).join(' + ')}
      <br />
      {column.members} runners{column.plusOnes ? ` + ${column.plusOnes}` : ''}
    </>
  )
}

/** "Wed 7 Jan, Social: 18 runners and 2 guests", a column's accessible name. */
function columnLabel(column) {
  const guests = column.plusOnes ? ` and ${column.plusOnes} guest${column.plusOnes === 1 ? '' : 's'}` : ''
  return `${formatDay(parseIsoDate(column.date))}, ${column.runs.map(runName).join(' + ')}: ${column.members} runners${guests}`
}

/**
 * Every run (R13): one track per club weekday plus Specials, each run date a
 * column of dots, one per member who ran (filled) and one per +1 (hollow).
 * Every track shares one date scale, from 1 January of the view's first
 * season to its latest run. The busiest day on each track is pink and
 * labelled, and each track's side panel gives its usual spot, its days and
 * its average, so the chart reads without hover.
 *
 * @param {{ tracks: ReturnType<typeof import('../../utils/dashboardMetrics').everyRunTracks> }} props
 */
export default function EveryRun({ tracks }) {
  const headingId = useId()
  const { tip, show, hide } = useTooltip()

  // The shared date scale: 1 Jan of the first season to the latest run, plus
  // a few days so the last column clears the edge (the mockup's +4).
  const scale = useMemo(() => {
    const dates = tracks.flatMap((track) => track.columns.map((column) => column.date)).sort()
    if (dates.length === 0) return null
    const start = new Date(Number(dates[0].slice(0, 4)), 0, 1)
    const span = (parseIsoDate(dates.at(-1)) - start) / DAY_MS + 4
    return { start, span }
  }, [tracks])

  return (
    <section className="block" aria-labelledby={headingId}>
      <div className="kick">
        <h2 id={headingId} className="display">
          Every run
        </h2>
        <p className="mono">One dot per runner · hollow = +1</p>
      </div>
      {scale ? (
        <div className="tracks">
          {tracks.map((track) => (
            <Track key={track.name} track={track} scale={scale} onShow={show} onHide={hide} />
          ))}
        </div>
      ) : (
        <p className="soft">No runs yet.</p>
      )}
      <Tooltip tip={tip} />
    </section>
  )
}

/**
 * One track: its dots in an SVG drawn to the measured width, and the side
 * panel. Memoized, so the parent's tooltip moves never redraw the dots.
 */
const Track = memo(function Track({ track, scale, onShow, onHide }) {
  const boxRef = useRef(null)
  const width = useWidth(boxRef, FALLBACK_WIDTH)
  // The one tabbable column (roving tab stop); -1 is the latest.
  const [active, setActive] = useState(-1)

  const { columns, busiest } = track
  const last = columns.length - 1
  const focusIndex = active < 0 ? last : Math.min(active, last)
  const height = busiest.count * (DOT + GAP) + HEADROOM
  const x = (iso) => INSET + ((parseIsoDate(iso) - scale.start) / DAY_MS / scale.span) * ((width ?? 0) - 2 * INSET)
  const dotY = (k) => height - 6 - k * (DOT + GAP)

  const showColumn = useCallback(
    (event) => onShow(columnTip(columns[Number(event.currentTarget.dataset.i)]), event),
    [columns, onShow]
  )
  const onFocus = (event) => {
    setActive(Number(event.currentTarget.dataset.i))
    showColumn(event)
  }
  const onKeyDown = (event) => {
    const next = rovingStep(event.key, focusIndex, columns.length)
    if (next === null) return
    event.preventDefault()
    setActive(next)
    event.currentTarget.querySelector(`[data-i="${next}"]`)?.focus()
  }

  const name = fullName(track)
  const subtitle = track.name === 'Specials' ? 'Weekends and holidays' : track.location
  // The busiest day's direct label flies over its column like a flag: above
  // the tallest column on the track, so no other dots can sit under it.
  const peakText = `${busiest.label} · ${busiest.count}`.toUpperCase()
  const peakAt = width === null ? null : fitLabel(x(busiest.date), peakText, LABEL_SIZE, MONO_ADVANCE, width, -4)

  return (
    <div className="run-track">
      <div className="box" ref={boxRef}>
        {width !== null && (
          <svg
            viewBox={`0 0 ${width} ${height}`}
            height={height}
            role="list"
            aria-label={`${name}: runners per run, one dot per runner`}
            onMouseLeave={onHide}
            onBlur={onHide}
            onKeyDown={onKeyDown}
          >
            <g aria-hidden="true">
              {columns.map((column) => {
                const peak = column.date === busiest.date
                const cx = x(column.date)
                return (
                  <g key={column.date} className={peak ? 'stack peak' : 'stack'}>
                    {Array.from({ length: column.members + column.plusOnes }, (_, k) => (
                      <circle key={k} className={k < column.members ? undefined : 'guest'} cx={cx} cy={dotY(k)} r={DOT / 2} />
                    ))}
                  </g>
                )
              })}
              <text className="peak-label" x={peakAt.x} y={dotY(busiest.count - 1) - 8} textAnchor={peakAt.anchor}>
                {peakText}
              </text>
            </g>
            {columns.map((column, i) => (
              <rect
                key={column.date}
                className="hit"
                role="listitem"
                x={x(column.date) - HIT / 2}
                y={0}
                width={HIT}
                height={height}
                tabIndex={i === focusIndex ? 0 : -1}
                data-i={i}
                aria-label={columnLabel(column)}
                onMouseMove={showColumn}
                onFocus={onFocus}
              />
            ))}
          </svg>
        )}
      </div>
      <div className="side">
        <div className="d">{track.name}</div>
        <div className="m">
          <span>{subtitle}</span>
          <span className="stats">
            {columns.length} days · avg {formatNumber(track.averageMembers, 1)}
          </span>
        </div>
      </div>
    </div>
  )
})
