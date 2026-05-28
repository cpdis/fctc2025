import { render, screen } from '@testing-library/react'
import DotPlot from './DotPlot'

const sample = [
  { label: 'Intervals', value: 12 },
  { label: 'Social', value: 8 },
  { label: 'Hills', value: 5 },
]

describe('DotPlot', () => {
  it('renders an accessible SVG with one dot per item', () => {
    const { container } = render(
      <DotPlot data={sample} ariaLabel="Runs by type" />
    )
    expect(
      screen.getByRole('img', { name: 'Runs by type' })
    ).toBeInTheDocument()

    const dots = container.querySelectorAll('[data-testid="dot-plot-dot"]')
    expect(dots).toHaveLength(sample.length)
  })

  it('renders labels and formatted values', () => {
    render(<DotPlot data={sample} format={(n) => `${n}x`} />)
    expect(screen.getByText('Intervals')).toBeInTheDocument()
    expect(screen.getByText('12x')).toBeInTheDocument()
  })

  it('renders empty and single-item data without throwing', () => {
    expect(() => render(<DotPlot data={[]} />)).not.toThrow()
    expect(() =>
      render(<DotPlot data={[{ label: 'Only', value: 3 }]} />)
    ).not.toThrow()
  })
})
