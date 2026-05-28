import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from '../../../utils/dataParser'
import { firstVsSecondHalf } from '../../../utils/dashboardMetrics'
import HalfSeasonSlopegraph from './HalfSeasonSlopegraph'

const fixtureDir = join(import.meta.dirname, '..', '..', '..', 'test', 'fixtures')
const data2025 = parseRunData(readFileSync(join(fixtureDir, '2025.csv'), 'utf-8'), 2025)

const MAX_ROWS = 12

describe('HalfSeasonSlopegraph', () => {
  it('renders one connector per shown member (capped)', () => {
    const total = firstVsSecondHalf(data2025).length
    const expected = Math.min(total, MAX_ROWS)
    const { container } = render(<HalfSeasonSlopegraph data={data2025} />)
    expect(container.querySelectorAll('[data-testid="slope-line"]')).toHaveLength(expected)
  })

  it('notes hidden members when the list exceeds the cap', () => {
    const total = firstVsSecondHalf(data2025).length
    const { queryByText } = render(<HalfSeasonSlopegraph data={data2025} />)
    if (total > MAX_ROWS) {
      expect(queryByText(/more not shown/i)).toBeInTheDocument()
    } else {
      expect(queryByText(/more not shown/i)).toBeNull()
    }
  })

  it('shows an empty state with no data', () => {
    const { getByText } = render(<HalfSeasonSlopegraph data={{ members: [], runs: [] }} />)
    expect(getByText(/Not enough runs/i)).toBeInTheDocument()
  })
})
