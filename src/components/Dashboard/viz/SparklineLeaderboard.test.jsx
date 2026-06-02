import { describe, it, expect } from 'vitest'
import { render, fireEvent } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from '../../../utils/dataParser'
import { memberMonthlyAttendance } from '../../../utils/dashboardMetrics'
import SparklineLeaderboard from './SparklineLeaderboard'

const fixtureDir = join(import.meta.dirname, '..', '..', '..', 'test', 'fixtures')
const data2025 = parseRunData(readFileSync(join(fixtureDir, '2025.csv'), 'utf-8'), 2025)
const data2026 = parseRunData(readFileSync(join(fixtureDir, '2026.csv'), 'utf-8'), 2026)

const TRUNCATE = 15

describe('SparklineLeaderboard', () => {
  it('truncates to 15 rows when there are more, with a Show all button', () => {
    const total = memberMonthlyAttendance(data2025).length
    expect(total).toBeGreaterThan(TRUNCATE) // fixture sanity: there is something to truncate
    const { getAllByTestId, getByRole } = render(<SparklineLeaderboard data={data2025} />)
    expect(getAllByTestId('leaderboard-row')).toHaveLength(TRUNCATE)
    expect(
      getByRole('button', { name: new RegExp(`Show all ${total} members`) })
    ).toBeInTheDocument()
  })

  it('expands to every row when Show all is clicked, then collapses again', () => {
    const total = memberMonthlyAttendance(data2025).length
    const { getAllByTestId, getByRole } = render(<SparklineLeaderboard data={data2025} />)

    fireEvent.click(getByRole('button', { name: /Show all/ }))
    expect(getAllByTestId('leaderboard-row')).toHaveLength(total)

    fireEvent.click(getByRole('button', { name: /Show fewer/ }))
    expect(getAllByTestId('leaderboard-row')).toHaveLength(TRUNCATE)
  })

  it('renders a sparkline per visible row', () => {
    const total = memberMonthlyAttendance(data2026).length
    const { container } = render(<SparklineLeaderboard data={data2026} />)
    const lines = container.querySelectorAll('[data-testid="sparkline-line"]')
    expect(lines.length).toBe(Math.min(TRUNCATE, total))
  })

  it('shows an empty state with no members', () => {
    const { getByText } = render(<SparklineLeaderboard data={{ members: [], runs: [] }} />)
    expect(getByText(/No member attendance/i)).toBeInTheDocument()
  })
})
