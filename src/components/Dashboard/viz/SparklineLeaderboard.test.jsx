import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from '../../../utils/dataParser'
import { memberMonthlyAttendance } from '../../../utils/dashboardMetrics'
import SparklineLeaderboard from './SparklineLeaderboard'

const fixtureDir = join(import.meta.dirname, '..', '..', '..', 'test', 'fixtures')
const data2025 = parseRunData(readFileSync(join(fixtureDir, '2025.csv'), 'utf-8'), 2025)
const data2026 = parseRunData(readFileSync(join(fixtureDir, '2026.csv'), 'utf-8'), 2026)

describe('SparklineLeaderboard', () => {
  it('renders one row per active member', () => {
    const expected = memberMonthlyAttendance(data2025).length
    const { getAllByTestId } = render(<SparklineLeaderboard data={data2025} />)
    expect(getAllByTestId('leaderboard-row')).toHaveLength(expected)
  })

  it('renders a sparkline per row', () => {
    const expected = memberMonthlyAttendance(data2026).length
    const { container } = render(<SparklineLeaderboard data={data2026} />)
    // Each row carries a 12-point sparkline (a polyline).
    const lines = container.querySelectorAll('[data-testid="sparkline-line"]')
    expect(lines.length).toBe(expected)
  })

  it('shows an empty state with no members', () => {
    const { getByText } = render(<SparklineLeaderboard data={{ members: [], runs: [] }} />)
    expect(getByText(/No member attendance/i)).toBeInTheDocument()
  })
})
