import { render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import Dashboard from './Dashboard'
import { snap2025, snap2026, snapAllTime } from '../test/snapshot'

// What App hands the page for each view: the view, the season before it, and
// every season merged (for all-time milestones).
const VIEWS = {
  2026: { data: snap2026, previous: snap2025 },
  2025: { data: snap2025, previous: null },
  all: { data: snapAllTime, previous: null },
}

function renderView(year) {
  const { data, previous } = VIEWS[year]
  return render(
    <MemoryRouter initialEntries={[`/?year=${year}`]}>
      <Dashboard data={data} previous={previous} allTime={snapAllTime} />
    </MemoryRouter>
  )
}

const sectionHeadings = () => screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)

describe('Dashboard', () => {
  beforeEach(() => {
    // No last-updated.json: the meta row leaves "Updated" out.
    vi.stubGlobal('fetch', vi.fn(() => Promise.resolve({ ok: false })))
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('2026 lays the sections out in the approved order (R9)', () => {
    const { container } = renderView(2026)
    expect(screen.getByRole('heading', { level: 1, name: 'The 2026 Season' })).toBeInTheDocument()
    expect(container.querySelector('.meta')).toHaveTextContent('Next Mon 28 Sep · Drift Intervals')
    expect(container.querySelector('.numbers')).toHaveTextContent('+38 on this time in 2025')
    expect(container.querySelector('.marquee')).toHaveTextContent('Aaron on 14 in a row')

    // On a roll beside the leaderboard, then the full-width sections.
    const pair = screen.getByRole('region', { name: 'Streaks and leaderboard' })
    expect(within(pair).getAllByRole('heading', { level: 3 }).map((h) => h.textContent)).toEqual([
      'On a roll',
      'Leaderboard',
    ])
    expect(sectionHeadings()).toEqual(['The Wall', 'Every run', 'Vs last year', 'Milestones ahead', 'Run log'])
    expect(pair.compareDocumentPosition(screen.getByRole('heading', { name: 'The Wall' }))).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING
    )
  })

  it.each([2025, 'all'])('%s has no Vs last year, and milestones still count all-time runs', (year) => {
    renderView(year)
    expect(sectionHeadings()).toEqual(['The Wall', 'Every run', 'Milestones ahead', 'Run log'])
    const bibs = within(screen.getByRole('region', { name: 'Milestones ahead' })).getAllByRole('listitem')
    expect(bibs.map((bib) => bib.querySelector('.who').textContent)).toEqual(['Col', 'Claire', 'Adam'])
  })
})
