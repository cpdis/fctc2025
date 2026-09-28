import { useId, useMemo, useRef, useState } from 'react'
import Tooltip, { useTooltip } from '../Poster/Tooltip'
import { formatNumber, formatShortDate, monthName, parseIsoDate } from '../Poster/format'
import { ANTON_ADVANCE, MONO_ADVANCE, fitLabel, rovingStep, useWidth } from './chartKit'

// Plot geometry in px, from the approved mockup. The right margin holds the
// end labels; under 600px the chart is shorter and the month labels thin to
// quarters. The narrow margin (100) still fits "2025 · 11,165" in Space Mono.
const FALLBACK_WIDTH = 900
const NARROW = 600
const LEFT = 48
const TOP = 16
const BOTTOM = 28
const YEAR_DAYS = 365
const MONTH_DAYS = 30.4

// Gridline steps: the smallest that needs at most six lines.
const STEPS = [100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000, 20000, 25000, 50000]
const MAX_LINES = 6

/**
 * Vs last year (R14): cumulative member-kilometres for the selected season
 * (pink) against the previous one (muted), labelled at both ends, with the gap
 * at the latest run drawn and labelled. Hidden (null) for All time and for a
 * season with no previous one.
 *
 * @param {{ progress: ReturnType<typeof import('../../utils/dashboardMetrics').seasonProgress> }} props
 */
export default function VsLastYear({ progress }) {
  const headingId = useId()
  if (!progress) return null
  return (
    <section className="block" aria-labelledby={headingId}>
      <div className="kick">
        <h2 id={headingId} className="display">
          Vs last year
        </h2>
        <p className="mono">Kilometres run together, cumulative</p>
      </div>
      <ProgressChart progress={progress} />
    </section>
  )
}

/** The chart, drawn to its measured width, with a crosshair on hover and on the arrow keys. */
function ProgressChart({ progress }) {
  const plotRef = useRef(null)
  const width = useWidth(plotRef, FALLBACK_WIDTH)
  const { tip, show, hide } = useTooltip()
  // Day of year under the crosshair, or null when it is hidden.
  const [cursor, setCursor] = useState(null)

  const { current, previous, previousAtLatest } = progress
  const now = current.points.at(-1)
  const then = previous.points.at(-1)
  // Keyboard stops: every run date of either season, in day order.
  const stops = useMemo(
    () => [...new Set([...current.points, ...previous.points].map((p) => p.dayOfYear))].sort((a, b) => a - b),
    [current, previous]
  )

  const W = width ?? 0
  const narrow = W < NARROW
  const H = narrow ? 240 : 300
  const right = narrow ? 100 : 120
  const top = Math.max(now.memberKm, then.memberKm)
  const step = STEPS.find((s) => top / s <= MAX_LINES) ?? STEPS.at(-1)
  const ymax = Math.max(step, Math.ceil(top / step) * step)
  const x = (day) => LEFT + (day / YEAR_DAYS) * (W - LEFT - right)
  const y = (km) => TOP + (1 - km / ymax) * (H - TOP - BOTTOM)
  // Both lines start from nothing on 1 January.
  const path = (points) =>
    [{ dayOfYear: 0, memberKm: 0 }, ...points]
      .map((p, i) => `${i ? 'L' : 'M'}${x(p.dayOfYear).toFixed(1)} ${y(p.memberKm).toFixed(1)}`)
      .join('')

  const gridlines = []
  for (let v = 0; v <= ymax; v += step) gridlines.push(v)

  const tipAt = (day) => {
    const upTo = (points) => points.filter((p) => p.dayOfYear <= day).at(-1)?.memberKm ?? 0
    return (
      <>
        <b>{formatShortDate(new Date(current.year, 0, 1 + day))}</b>
        <br />
        {current.year}: {day <= now.dayOfYear ? `${formatNumber(upTo(current.points))} km` : '–'}
        <br />
        {previous.year}: {formatNumber(upTo(previous.points))} km
      </>
    )
  }

  const moveTo = (day, event) => {
    setCursor(day)
    show(tipAt(day), event)
  }
  const clear = () => {
    setCursor(null)
    hide()
  }

  // The pointer snaps to whole days, so the crosshair, the date and both
  // totals always describe the same day.
  const onMouseMove = (event) => {
    const box = event.currentTarget.getBoundingClientRect()
    const scaleX = box.width ? W / box.width : 1
    const day = Math.round((((event.clientX - box.left) * scaleX - LEFT) / (W - LEFT - right)) * YEAR_DAYS)
    if (day >= 0 && day <= YEAR_DAYS) moveTo(day, event)
    else clear()
  }
  // Focus opens on the latest run; the arrows step run date by run date.
  const onKeyDown = (event) => {
    const at = stops.findLastIndex((day) => day <= (cursor ?? now.dayOfYear))
    const next = rovingStep(event.key, Math.max(0, at), stops.length)
    if (next === null) return
    event.preventDefault()
    moveTo(stops[next], event)
  }

  const nowText = `${current.year} · ${formatNumber(now.memberKm)} km`.toUpperCase()
  const gapText = `${previous.year} by now · ${formatNumber(previousAtLatest)}`.toUpperCase()
  const thenText = `${previous.year} · ${formatNumber(then.memberKm)}`.toUpperCase()
  const nowSize = narrow ? 18 : 22
  // End labels sit right of their point, or left of it when they would run
  // past the edge (a phone, or a season late in the year).
  const nowAt = fitLabel(x(now.dayOfYear), nowText, nowSize, ANTON_ADVANCE, W)
  const gapAt = fitLabel(x(now.dayOfYear), gapText, 11, MONO_ADVANCE, W)
  const thenAt = fitLabel(x(then.dayOfYear), thenText, 11, MONO_ADVANCE, W, 8)
  const latest = formatShortDate(parseIsoDate(now.date))

  return (
    <div className="chart">
      <div ref={plotRef}>
        {width !== null && (
          <svg
            className="progress"
            viewBox={`0 0 ${W} ${H}`}
            height={H}
            role="img"
            tabIndex={0}
            aria-label={
              `Kilometres run together, ${current.year} against ${previous.year}: ` +
              `${formatNumber(now.memberKm)} km by ${latest}; ${previous.year} had ` +
              `${formatNumber(previousAtLatest)} km by then and finished on ${formatNumber(then.memberKm)} km.`
            }
            onMouseMove={onMouseMove}
            onMouseLeave={clear}
            onFocus={(event) => moveTo(now.dayOfYear, event)}
            onBlur={clear}
            onKeyDown={onKeyDown}
          >
            {gridlines.map((v) => (
              <g key={v}>
                <line className="gridline" x1={LEFT} x2={W - right} y1={y(v)} y2={y(v)} />
                <text className="axis" x={LEFT - 8} y={y(v) + 4} textAnchor="end">
                  {formatNumber(v)}
                </text>
              </g>
            ))}
            {Array.from({ length: 12 }, (_, m) =>
              narrow && m % 3 ? null : (
                <text key={m} className="axis" x={x(m * MONTH_DAYS + 2)} y={H - 8}>
                  {monthName(m).toUpperCase()}
                </text>
              )
            )}
            <path className="line-then" d={path(previous.points)} />
            <path className="line-now" d={path(current.points)} />

            {/* The gap at the latest run: this season's point over last season's on the same date. */}
            <line className="gap" x1={x(now.dayOfYear)} x2={x(now.dayOfYear)} y1={y(now.memberKm)} y2={y(previousAtLatest)} />
            <circle className="dot-then" cx={x(now.dayOfYear)} cy={y(previousAtLatest)} r={4} />
            <circle className="dot-now" cx={x(now.dayOfYear)} cy={y(now.memberKm)} r={5} />

            {/* Flipped left, the label lifts clear of this season's line, which rises into the point. */}
            <text
              className="label-now"
              x={nowAt.x}
              y={y(now.memberKm) + (nowAt.flipped ? -10 : 2)}
              textAnchor={nowAt.anchor}
              fontSize={nowSize}
            >
              {nowText}
            </text>
            <text className="label" x={gapAt.x} y={y(previousAtLatest) + 14} textAnchor={gapAt.anchor}>
              {gapText}
            </text>
            <text className="label" x={thenAt.x} y={y(then.memberKm) + 4} textAnchor={thenAt.anchor}>
              {thenText}
            </text>

            {cursor !== null && <line className="cross" x1={x(cursor)} x2={x(cursor)} y1={TOP} y2={H - BOTTOM} />}
          </svg>
        )}
      </div>
      <Tooltip tip={tip} />
    </div>
  )
}
