import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from '../../../utils/dataParser'
import { runTypeMonthlyCounts, monthAxis } from '../../../utils/dashboardMetrics'
import RunTypeSmallMultiples from './RunTypeSmallMultiples'

const fixtureDir = join(import.meta.dirname, '..', '..', '..', 'test', 'fixtures')
const data2025 = parseRunData(readFileSync(join(fixtureDir, '2025.csv'), 'utf-8'), 2025)

describe('RunTypeSmallMultiples', () => {
  it('renders one panel per run type', () => {
    const expected = runTypeMonthlyCounts(data2025).length
    const { getAllByTestId } = render(<RunTypeSmallMultiples data={data2025} />)
    expect(getAllByTestId('small-multiple-panel')).toHaveLength(expected)
  })

  it('renders one bar per axis month in every panel', () => {
    const { getAllByTestId } = render(<RunTypeSmallMultiples data={data2025} />)
    const panels = runTypeMonthlyCounts(data2025).length
    expect(getAllByTestId('mini-bar')).toHaveLength(panels * monthAxis(data2025.runs).length)
  })

  it('shows an empty state with no runs', () => {
    const { getByText } = render(<RunTypeSmallMultiples data={{ runs: [] }} />)
    expect(getByText(/No runs recorded/i)).toBeInTheDocument()
  })
})
