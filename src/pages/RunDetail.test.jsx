import { describe, it, expect } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseRunData } from '../utils/dataParser'
import RunDetail from './RunDetail'

// The dated snapshot (2026-09-27): 2025 runs to Wed 31 Dec, 2026 to Fri 25 Sep.
// Under jsdom import.meta.url is not a file: URL; use import.meta.dirname.
const snapshotDir = join(import.meta.dirname, '..', '..', 'fixtures', 'attendance', '2026-09-27')
const season = (year) => parseRunData(readFileSync(join(snapshotDir, `${year}.csv`), 'utf-8'), year)
const seasons = { 2025: season(2025), 2026: season(2026) }

// Both mount points, as App routes them.
function renderRun(path, store = seasons) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/run/:runId" element={<RunDetail seasons={store} />} />
        <Route path="/dashboard/run/:runId" element={<RunDetail seasons={store} />} />
      </Routes>
    </MemoryRouter>
  )
}

// A tiny season: Alice and Cara plus two +1s on a 5.3 km run, and a run
// with attendance but no km recorded.
const TINY_CSV = [
  "Date,Meet,Run,Approx kms,Actual kms,Alice,Bob,Cara,+1's",
  '"Wed, 7-Jan",Drift,Intervals,5,5.3,x,,x,2',
  '"Fri, 9-Jan",Filament,Social,,,x,x,,1',
].join('\n')
const tiny = { 2026: parseRunData(TINY_CSV, 2026) }

const title = () => screen.getByRole('heading', { level: 1 })
const backLink = (view) => screen.getByRole('link', { name: `Back to ${view}` })
// A headline number's value, found by its label ("Route", "Run together").
const number = (label) => screen.getByText(label, { selector: '.l' }).previousElementSibling

describe('RunDetail', () => {
  // Covers AE6: the 31 Dec 2025 row from the 2025 view opens that exact run.
  it('opens the run by id from its own season view', () => {
    renderRun('/run/2025-12-31-intervals?year=2025')
    expect(title()).toHaveAccessibleName('Wed 31 Dec 2025')
    expect(number('Runners')).toHaveTextContent('12')
    expect(backLink('2025 Season')).toHaveAttribute('href', '/?year=2025')
  })

  // Covers AE6: any 2025 row from All time opens the 2025 run, and the page
  // keeps the selected view.
  it('resolves a 2025 id in 2025 when the view is All time, under /dashboard', () => {
    renderRun('/dashboard/run/2025-01-03-soft-sand?year=all')
    expect(title()).toHaveAccessibleName('Fri 3 Jan 2025')
    expect(backLink('All Time')).toHaveAttribute('href', '/dashboard?year=all')
    expect(screen.getByRole('link', { name: 'Dashboard' })).toHaveAttribute('href', '/dashboard?year=all')
  })

  it('resolves the id in its own season whatever ?year says', () => {
    renderRun('/run/2025-01-03-soft-sand?year=2026')
    expect(title()).toHaveAccessibleName('Fri 3 Jan 2025')
    expect(backLink('2026 Season')).toHaveAttribute('href', '/?year=2026')
  })

  it('shows "Run not found" for an old numeric id, linking back to the same year', () => {
    renderRun('/run/12?year=2025')
    expect(title()).toHaveAccessibleName('Run not found')
    expect(backLink('2025 Season')).toHaveAttribute('href', '/?year=2025')
  })

  it('shows "Run not found" for an unknown id under /dashboard', () => {
    renderRun('/dashboard/run/2025-12-30-intervals?year=all')
    expect(title()).toHaveAccessibleName('Run not found')
    expect(backLink('All Time')).toHaveAttribute('href', '/dashboard?year=all')
  })

  it('links back to the view it was opened from, run-log filters included', () => {
    renderRun('/dashboard/run/2026-09-25-river-loop?year=2026&type=River+Loop&q=aaron')
    expect(backLink('2026 Season')).toHaveAttribute('href', '/dashboard?year=2026&type=River+Loop&q=aaron')
  })

  it('shows the type as a club-run tag, with the location', () => {
    renderRun('/run/2025-12-31-intervals?year=2025')
    expect(screen.getByText('Intervals')).toHaveClass('tag')
    expect(screen.getByText('Intervals')).not.toHaveClass('sp')
    expect(screen.getByText('Where').parentElement).toHaveTextContent('Where Filament')
    expect(screen.queryByText('Event')).not.toBeInTheDocument()
  })

  it('shows a special gold, with its event', () => {
    renderRun('/run/2025-12-14-half-xmas?year=2025')
    expect(title()).toHaveAccessibleName('Sun 14 Dec 2025')
    expect(screen.getByText('Half Marathon')).toHaveClass('tag', 'sp')
    expect(screen.getByText('Event').parentElement).toHaveTextContent('Event Xmas')
  })

  it('lists members in sheet order, then one entry per +1, and counts member-km without the +1s', () => {
    renderRun('/run/2026-01-07-intervals?year=2026', tiny)
    const who = screen.getByRole('region', { name: 'Who ran' })
    expect(within(who).getAllByRole('listitem').map((item) => item.textContent)).toEqual([
      'Alice',
      'Cara',
      '+1',
      '+1',
    ])
    expect(within(who).getByText('2 runners and 2 plus ones')).toBeInTheDocument()
    expect(number('Runners')).toHaveTextContent('2')
    expect(number('Plus ones')).toHaveTextContent('2')
    expect(number('Route')).toHaveTextContent('5.3km')
    // 5.3 km x 2 members; the two +1s do not count.
    expect(number('Run together')).toHaveTextContent('10.6km')
  })

  // Review finding 12.
  it('shows "—" for a run with attendance but no km, never a bare 0', () => {
    renderRun('/run/2026-01-09-social?year=2026', tiny)
    expect(number('Route')).toHaveTextContent(/^—$/)
    expect(number('Run together')).toHaveTextContent(/^—$/)
    expect(screen.getByText('No distance logged')).toBeInTheDocument()
    expect(screen.queryByText('0')).not.toBeInTheDocument()
  })
})
