import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from '../../../utils/dataParser'
import { runFrequencyByDate } from '../../../utils/dashboardMetrics'
import CalendarHeatmap, {
  quartileThresholds,
  levelForCount,
  buildCalendarData,
} from './CalendarHeatmap'

const fixtureDir = join(import.meta.dirname, '..', '..', '..', 'test', 'fixtures')
const data2025 = parseRunData(readFileSync(join(fixtureDir, '2025.csv'), 'utf-8'), 2025)

describe('CalendarHeatmap data mapping', () => {
  it('derives ascending quartile thresholds from nonzero counts', () => {
    const t = quartileThresholds([0, 1, 2, 3, 4, 0, 8])
    expect(t).toHaveLength(3)
    expect(t[0]).toBeLessThanOrEqual(t[1])
    expect(t[1]).toBeLessThanOrEqual(t[2])
  })

  it('buckets counts into 0..4 with 0 reserved for empty days', () => {
    const t = [2, 4, 6]
    expect(levelForCount(0, t)).toBe(0)
    expect(levelForCount(1, t)).toBe(1)
    expect(levelForCount(3, t)).toBe(2)
    expect(levelForCount(5, t)).toBe(3)
    expect(levelForCount(99, t)).toBe(4)
  })

  it('fills the full year so empty days exist as level 0', () => {
    const freq = runFrequencyByDate(data2025.runs)
    // Use a fixed "today" past year-end so the full year is generated.
    const cal = buildCalendarData(freq, 2025, new Date('2027-01-01'))
    expect(cal.length).toBe(365) // 2025 is not a leap year
    // Every real run day is present with its real count.
    const byDay = new Map(cal.map((d) => [d.date, d]))
    for (const f of freq) {
      expect(byDay.get(f.date).count).toBe(f.count)
      expect(byDay.get(f.date).level).toBeGreaterThanOrEqual(1)
    }
    // At least some days are empty/level 0 (no fabricated attendance).
    expect(cal.some((d) => d.count === 0 && d.level === 0)).toBe(true)
  })

  it('clamps the range to today for a partial current year', () => {
    const freq = runFrequencyByDate(data2025.runs)
    const cal = buildCalendarData(freq, 2025, new Date('2025-03-15'))
    // Should not extend past the clamp date.
    expect(cal[cal.length - 1].date <= '2025-03-15').toBe(true)
  })
})

describe('CalendarHeatmap render', () => {
  it('renders the card with a title and the calendar', () => {
    const { getByText, container } = render(
      <CalendarHeatmap data={data2025} year={2025} />
    )
    expect(getByText('Run Calendar')).toBeInTheDocument()
    // react-activity-calendar renders an SVG of day cells.
    expect(container.querySelector('svg')).toBeInTheDocument()
  })

  it('shows an empty state when there are no runs', () => {
    const { getByText } = render(<CalendarHeatmap data={{ runs: [] }} year={2025} />)
    expect(getByText(/No runs recorded/i)).toBeInTheDocument()
  })
})
