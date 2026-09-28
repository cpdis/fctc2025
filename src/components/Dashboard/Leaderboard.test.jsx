import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import Leaderboard from './Leaderboard'
import { snap2026 } from '../../test/snapshot'

const board = (by) => screen.getByRole('list', { name: `Top 10 by ${by}` })
const rows = (by) => within(board(by)).getAllByRole('listitem').map((row) => row.textContent)

describe('Leaderboard', () => {
  it('ranks the top 10 by runs, with the value printed on each row', () => {
    render(<Leaderboard leaderboard={snap2026.leaderboard} distanceLeaderboard={snap2026.distanceLeaderboard} />)
    expect(screen.getByRole('button', { name: 'Runs' })).toHaveAttribute('aria-pressed', 'true')
    expect(rows('runs')).toHaveLength(10)
    expect(rows('runs').slice(0, 3)).toEqual(['1Aaron89', '2Scott81', '3Alex 👑78'])
  })

  it('switches to km, where the leader fills the bar', () => {
    const { container } = render(
      <Leaderboard leaderboard={snap2026.leaderboard} distanceLeaderboard={snap2026.distanceLeaderboard} />
    )
    fireEvent.click(screen.getByRole('button', { name: 'Km' }))
    expect(screen.getByRole('button', { name: 'Km' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: 'Runs' })).toHaveAttribute('aria-pressed', 'false')
    expect(rows('km')[0]).toBe('1Aaron927')
    const bars = [...container.querySelectorAll('.bar')]
    expect(bars[0]).toHaveStyle({ width: '100%' })
    expect(parseFloat(bars[9].style.width)).toBeLessThan(100)
  })

  it('says so when nobody has run yet', () => {
    render(<Leaderboard leaderboard={[]} distanceLeaderboard={[]} />)
    expect(screen.getByText('No runs yet.')).toBeInTheDocument()
  })
})
