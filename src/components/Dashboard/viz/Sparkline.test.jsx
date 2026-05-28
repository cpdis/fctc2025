import { render, screen } from '@testing-library/react'
import Sparkline from './Sparkline'

describe('Sparkline', () => {
  it('renders an accessible SVG with a polyline for multi-point data', () => {
    const { container } = render(
      <Sparkline data={[1, 3, 2, 5, 4]} ariaLabel="Weekly pace" />
    )
    const svg = screen.getByRole('img', { name: 'Weekly pace' })
    expect(svg).toBeInTheDocument()

    const line = container.querySelector('[data-testid="sparkline-line"]')
    expect(line).toBeInTheDocument()
    // 5 points → 5 coordinate pairs in the polyline.
    expect(line.getAttribute('points').trim().split(/\s+/)).toHaveLength(5)
  })

  it('draws the last-point dot by default', () => {
    const { container } = render(<Sparkline data={[1, 2, 3]} />)
    expect(
      container.querySelector('[data-testid="sparkline-dot"]')
    ).toBeInTheDocument()
  })

  it('renders a single point without a line and without throwing', () => {
    const { container } = render(<Sparkline data={[7]} />)
    // No polyline with a single point, but it should still render the dot.
    expect(
      container.querySelector('[data-testid="sparkline-line"]')
    ).not.toBeInTheDocument()
    expect(
      container.querySelector('[data-testid="sparkline-dot"]')
    ).toBeInTheDocument()
  })

  it('renders empty data without throwing', () => {
    expect(() => render(<Sparkline data={[]} />)).not.toThrow()
    expect(() => render(<Sparkline />)).not.toThrow()
  })
})
