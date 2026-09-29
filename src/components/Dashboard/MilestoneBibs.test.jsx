import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import MilestoneBibs from './MilestoneBibs'
import { milestoneShortlist } from '../../utils/clubDays'
import { snapAllTime } from '../../test/snapshot'

// All-time runs through the latest run (27 Sep 2026 snapshot), both seasons summed.
const allTimeTotals = Object.values(snapAllTime.memberTotals).map(({ name, totalRuns }) => ({ name, runs: totalRuns }))

describe('MilestoneBibs', () => {
  it('shows Col, Claire and Adam for the current all-time totals, closest first', () => {
    render(<MilestoneBibs shortlist={milestoneShortlist(allTimeTotals)} />)
    expect(screen.getByRole('region', { name: 'Milestones ahead' })).toBeInTheDocument()
    const bibs = screen.getAllByRole('listitem').map((bib) => bib.textContent)
    expect(bibs).toEqual(['Col2 to 150 · now 148', 'Claire3 to 50 · now 47', 'Adam7 to 150 · now 143'])
  })

  it("says no one's close when the shortlist is empty", () => {
    render(<MilestoneBibs shortlist={[]} />)
    expect(screen.getByText("No one's close to a milestone yet")).toBeInTheDocument()
    expect(screen.queryByRole('list')).toBeNull()
  })
})
