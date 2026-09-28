import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import EveryRun from './EveryRun'
import { everyRunTracks } from '../../utils/dashboardMetrics'
import { snap2025, snap2026 } from '../../test/snapshot'

const tracks2026 = everyRunTracks(snap2026)
const tracks2025 = everyRunTracks(snap2025)

const track = (name) => screen.getByRole('list', { name: `${name}: runners per run, one dot per runner` })
const trackNames = () => screen.getAllByRole('list').map((list) => list.getAttribute('aria-label').split(':')[0])

describe('EveryRun', () => {
  it('draws four tracks for 2026 and three for 2025', () => {
    const { unmount } = render(<EveryRun tracks={tracks2026} />)
    expect(trackNames()).toEqual(['Monday', 'Wednesday', 'Friday', 'Specials'])
    unmount()

    render(<EveryRun tracks={tracks2025} />)
    expect(trackNames()).toEqual(['Wednesday', 'Friday', 'Specials'])
  })

  it('reads without hover: usual spot, days and average beside each track, the busiest day labelled', () => {
    const { container } = render(<EveryRun tracks={tracks2026} />)
    const sides = [...container.querySelectorAll('.run-track .side')].map((side) => side.textContent)
    expect(sides[0]).toBe('MonDrift38 days · avg 6.0')
    expect(sides[3]).toBe('SpecialsWeekends and holidays2 days · avg 11.5')

    const wednesday = track('Wednesday')
    expect(within(wednesday).getByText('SOCIAL · 18')).toBeInTheDocument()
    // The busiest day's dots are pink; no other column's are.
    expect(wednesday.querySelectorAll('.stack.peak')).toHaveLength(1)
    expect(wednesday.querySelectorAll('.stack.peak circle')).toHaveLength(18)
  })

  it('gives one filled dot per runner and one hollow dot per +1', () => {
    render(<EveryRun tracks={tracks2026} />)
    const wednesday = tracks2026.find((t) => t.name === 'Wed')
    const members = wednesday.columns.reduce((sum, c) => sum + c.members, 0)
    const guests = wednesday.columns.reduce((sum, c) => sum + c.plusOnes, 0)
    expect(track('Wednesday').querySelectorAll('circle.guest')).toHaveLength(guests)
    expect(track('Wednesday').querySelectorAll('circle:not(.guest)')).toHaveLength(members)
  })

  it('a keyboard user tabs to a column and sees the same tooltip as hovering it', () => {
    render(<EveryRun tracks={tracks2026} />)
    const monday = track('Monday')
    // One tab stop per track: its latest column.
    const [column] = monday.querySelectorAll('[tabindex="0"]')
    expect(monday.querySelectorAll('[tabindex="0"]')).toHaveLength(1)
    expect(column).toHaveAttribute('aria-label', 'Mon 21 Sep, Cruise: 7 runners')

    fireEvent.focus(column)
    const focused = screen.getByRole('tooltip').textContent
    expect(focused).toBe('Mon 21 SepCruise7 runners')
    fireEvent.blur(column)
    expect(screen.queryByRole('tooltip')).toBeNull()

    fireEvent.mouseMove(column, { clientX: 10, clientY: 10 })
    expect(screen.getByRole('tooltip').textContent).toBe(focused)
    fireEvent.mouseLeave(monday)
    expect(screen.queryByRole('tooltip')).toBeNull()
  })

  it('names both runs and the +1s on a shared date, and steps along with the arrow keys', () => {
    render(<EveryRun tracks={tracks2026} />)
    const monday = track('Monday')
    const invasionDay = within(monday).getByRole('listitem', { name: /^Mon 26 Jan/ })
    expect(invasionDay).toHaveAccessibleName(
      'Mon 26 Jan, Half Marathon · Invasion Day + 10K · Invasion Day: 6 runners and 1 guest'
    )
    fireEvent.focus(invasionDay)
    expect(screen.getByRole('tooltip')).toHaveTextContent('6 runners + 1')

    fireEvent.keyDown(invasionDay, { key: 'ArrowRight' })
    expect(document.activeElement).toHaveAccessibleName(/^Mon 2 Feb/)
    expect(document.activeElement).toHaveAttribute('tabindex', '0')
    fireEvent.keyDown(document.activeElement, { key: 'Home' })
    expect(document.activeElement).toHaveAccessibleName(/^Mon 5 Jan/)
  })

  it('says so when the view has no runs yet', () => {
    render(<EveryRun tracks={[]} />)
    expect(screen.getByText('No runs yet.')).toBeInTheDocument()
  })
})
