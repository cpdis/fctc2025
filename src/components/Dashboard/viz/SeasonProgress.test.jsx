import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from '../../../utils/dataParser'
import SeasonProgress from './SeasonProgress'

// Under jsdom import.meta.url is not a file: URL; use import.meta.dirname.
const fixtureDir = join(import.meta.dirname, '..', '..', '..', 'test', 'fixtures')
const data2025 = parseRunData(readFileSync(join(fixtureDir, '2025.csv'), 'utf-8'), 2025)
const data2026 = parseRunData(readFileSync(join(fixtureDir, '2026.csv'), 'utf-8'), 2026)

describe('SeasonProgress', () => {
  it('renders the chart container with a title for the full season', () => {
    const { container, getByText } = render(<SeasonProgress data={data2025} />)
    expect(getByText('Season Progress')).toBeInTheDocument()
    // Recharts' ResponsiveContainer needs real layout (0px under jsdom) so the
    // inner SVG may not mount; assert the chart wrapper is present instead.
    expect(container.querySelector('.recharts-responsive-container')).toBeInTheDocument()
  })

  it('renders for a partial season without throwing', () => {
    expect(() => render(<SeasonProgress data={data2026} />)).not.toThrow()
  })

  it('shows an empty state when there are no dated runs', () => {
    const { getByText } = render(<SeasonProgress data={{ runs: [] }} />)
    expect(getByText(/No dated runs/i)).toBeInTheDocument()
  })
})
