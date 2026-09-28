import { describe, it, expect } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
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

const backLink = () => screen.getByRole('link', { name: 'Back' })

describe('RunDetail', () => {
  // Covers AE6: the 31 Dec 2025 row from the 2025 view opens that exact run.
  it('opens the run by id from its own season view', () => {
    renderRun('/run/2025-12-31-intervals?year=2025')
    expect(screen.getByRole('heading', { level: 1, name: 'Wed, 31-Dec' })).toBeInTheDocument()
    expect(screen.getByText('12')).toBeInTheDocument()
    expect(screen.getByText('2025 Season')).toBeInTheDocument()
    expect(backLink()).toHaveAttribute('href', '/?year=2025')
  })

  // Covers AE6: any 2025 row from All time opens the 2025 run, and the header
  // keeps the selected view.
  it('resolves a 2025 id in 2025 when the view is All time, under /dashboard', () => {
    renderRun('/dashboard/run/2025-01-03-soft-sand?year=all')
    expect(screen.getByRole('heading', { level: 1, name: 'Fri, 3-Jan' })).toBeInTheDocument()
    expect(screen.getByText('All Time')).toBeInTheDocument()
    expect(backLink()).toHaveAttribute('href', '/dashboard?year=all')
  })

  it('resolves the id in its own season whatever ?year says', () => {
    renderRun('/run/2025-01-03-soft-sand?year=2026')
    expect(screen.getByRole('heading', { level: 1, name: 'Fri, 3-Jan' })).toBeInTheDocument()
    expect(screen.getByText('2026 Season')).toBeInTheDocument()
  })

  it('shows "Run not found" for an old numeric id, linking back to the same year', () => {
    renderRun('/run/12?year=2025')
    expect(screen.getByRole('heading', { name: 'Run not found' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to Dashboard' })).toHaveAttribute('href', '/?year=2025')
  })

  it('shows "Run not found" for an unknown id under /dashboard', () => {
    renderRun('/dashboard/run/2025-12-30-intervals?year=all')
    expect(screen.getByRole('heading', { name: 'Run not found' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to Dashboard' })).toHaveAttribute('href', '/dashboard?year=all')
  })

  it('links back to the view it was opened from, run-log filters included', () => {
    renderRun('/dashboard/run/2026-09-25-river-loop?year=2026&type=River+Loop&q=aaron')
    expect(backLink()).toHaveAttribute('href', '/dashboard?year=2026&type=River+Loop&q=aaron')
  })

  // Covers AE7 for the run page: the header's year switch drops the run-log
  // filters and only moves the header and the Back link; the run stays.
  it('keeps the run and drops the filters when the header switches year', () => {
    renderRun('/run/2026-09-25-river-loop?year=2026&type=River+Loop&month=Sep')
    fireEvent.change(screen.getByRole('combobox', { name: 'Select season' }), { target: { value: '2025' } })
    expect(screen.getByRole('heading', { level: 1, name: 'Fri, 25-Sep' })).toBeInTheDocument()
    expect(screen.getByText('2025 Season')).toBeInTheDocument()
    expect(backLink()).toHaveAttribute('href', '/?year=2025')
  })

  it('shows "—" for a run with attendance but no km, never a bare 0', () => {
    const csv = [
      "Date,Meet,Run,Approx kms,Actual kms,Alice,Bob,+1's",
      '"Wed, 7-Jan",Drift,Intervals,,,x,x,0',
    ].join('\n')
    renderRun('/run/2026-01-07-intervals?year=2026', { 2026: parseRunData(csv, 2026) })
    expect(screen.getByText('Kilometers').previousElementSibling).toHaveTextContent('—')
    expect(screen.queryByText('Combined Distance')).not.toBeInTheDocument()
    // A falsy `{km && …}` guard renders a stray "0" text node; there is none.
    expect(screen.queryByText('0')).not.toBeInTheDocument()
  })
})
