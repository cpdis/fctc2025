import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import OnARoll, { streakRule } from './OnARoll'
import { onARoll } from '../../utils/dashboardMetrics'
import { snap2025, snap2026, snapAllTime } from '../../test/snapshot'

const streakRows = () => screen.getAllByRole('listitem').map((row) => row.textContent)

describe('OnARoll', () => {
  it('2026: current streaks as squares with the count, season bests with dates, the Mon/Wed/Fri rule', () => {
    const { container } = render(<OnARoll {...onARoll(snap2026)} />)
    expect(screen.getByText('Current streaks')).toBeInTheDocument()
    expect(streakRows()).toEqual(['Aaron14', 'Cam5', 'Scott2', 'Kate B2', 'Alex B1'])
    // One square per club day in the streak, hidden from assistive tech.
    const aaron = container.querySelector('.streak .squares')
    expect(aaron).toHaveAttribute('aria-hidden', 'true')
    expect(aaron.querySelectorAll('i')).toHaveLength(14)

    const best = container.querySelector('.best')
    expect(best.firstChild).toHaveTextContent('Season best')
    expect(best).toHaveTextContent('Aaron 14 (26 Aug – 25 Sep) · Alex 👑 9 (2 Jan – 21 Jan) · Scott 5 (21 Jan – 30 Jan)')
    expect(
      screen.getByText(
        "A streak counts Monday, Wednesday and Friday club runs in a row. Any run that day counts. Weekend and holiday specials don't add to it or break it."
      )
    ).toBeInTheDocument()
  })

  it('2025: streaks at season end, Scott on 49, the Wed/Fri rule', () => {
    render(<OnARoll {...onARoll(snap2025)} />)
    expect(screen.getByText('At season end')).toBeInTheDocument()
    expect(streakRows()[0]).toBe('Scott49')
    expect(screen.getByText(/^A streak counts Wednesday and Friday club runs in a row\./)).toBeInTheDocument()
  })

  it('All time: longest streaks, with the year on each date', () => {
    const { container } = render(<OnARoll {...onARoll(snapAllTime)} allTime />)
    const best = container.querySelector('.best')
    expect(best.firstChild).toHaveTextContent('Longest streaks')
    expect(best).toHaveTextContent('Scott 54 (3 Jan 2025 – 9 Jul 2025) · Cam 33 (3 Jan 2025 – 25 Apr 2025)')
  })

  it('says so when nobody is on a streak', () => {
    render(<OnARoll current={[]} bests={[]} weekdays={[]} finished={false} />)
    expect(screen.getByText('Nobody is on a streak right now.')).toBeInTheDocument()
    expect(streakRule([])).toMatch(/^A streak counts club runs in a row\./)
  })
})
