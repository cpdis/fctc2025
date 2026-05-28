import { render, screen } from '@testing-library/react'
import Slopegraph from './Slopegraph'

const sample = [
  { label: 'Alice', left: 10, right: 18 },
  { label: 'Bob', left: 14, right: 9 },
  { label: 'Cleo', left: 8, right: 8 },
]

describe('Slopegraph', () => {
  it('renders an accessible SVG with one connector line per series', () => {
    const { container } = render(
      <Slopegraph data={sample} ariaLabel="Attendance change" />
    )
    expect(
      screen.getByRole('img', { name: 'Attendance change' })
    ).toBeInTheDocument()

    const lines = container.querySelectorAll('[data-testid="slope-line"]')
    expect(lines).toHaveLength(sample.length)
  })

  it('direct-labels each series', () => {
    render(<Slopegraph data={sample} />)
    // Left labels print "name value".
    expect(screen.getByText(/Alice 10/)).toBeInTheDocument()
    expect(screen.getByText(/Bob 14/)).toBeInTheDocument()
  })

  it('renders empty and single-series data without throwing', () => {
    expect(() => render(<Slopegraph data={[]} />)).not.toThrow()
    expect(() =>
      render(<Slopegraph data={[{ label: 'Solo', left: 5, right: 9 }]} />)
    ).not.toThrow()
  })
})
