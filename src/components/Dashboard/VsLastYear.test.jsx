import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import VsLastYear from './VsLastYear'
import { seasonProgress } from '../../utils/dashboardMetrics'
import { snap2025, snap2026, snapAllTime } from '../../test/snapshot'

const progress2026 = seasonProgress(snap2026, snap2025)
const chart = () =>
  screen.getByRole('img', {
    name:
      'Kilometres run together, 2026 against 2025: 9,889 km by 25 Sep; ' +
      '2025 had 8,263 km by then and finished on 11,165 km.',
  })

describe('VsLastYear', () => {
  it('is absent for 2025 (no previous season) and for All time', () => {
    const { container, rerender } = render(<VsLastYear progress={seasonProgress(snap2025, null)} />)
    expect(container).toBeEmptyDOMElement()
    rerender(<VsLastYear progress={seasonProgress(snapAllTime, snap2025)} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('labels both ends and the gap at the latest run, so it reads without hover', () => {
    render(<VsLastYear progress={progress2026} />)
    expect(screen.getByRole('heading', { level: 2, name: 'Vs last year' })).toBeInTheDocument()
    expect(chart()).toBeInTheDocument()
    expect(screen.getByText('2026 · 9,889 KM')).toBeInTheDocument()
    expect(screen.getByText('2025 BY NOW · 8,263')).toBeInTheDocument()
    expect(screen.getByText('2025 · 11,165')).toBeInTheDocument()
    // Month labels: all twelve at desktop width (jsdom draws at 900px).
    expect(screen.getByText('FEB')).toBeInTheDocument()
  })

  it('focus shows the latest run against last year, and the arrows step run date by run date', () => {
    const { container } = render(<VsLastYear progress={progress2026} />)
    fireEvent.focus(chart())
    const tip = () => screen.getByRole('tooltip')
    expect(tip().textContent).toBe('25 Sep2026: 9,889 km2025: 8,263 km')
    expect(container.querySelector('.cross')).not.toBeNull()

    fireEvent.keyDown(chart(), { key: 'ArrowLeft' })
    expect(tip()).toHaveTextContent('24 Sep')
    fireEvent.keyDown(chart(), { key: 'End' })
    // Past this season's latest run only last season has a line.
    expect(tip().textContent).toBe('31 Dec2026: –2025: 11,165 km')

    fireEvent.blur(chart())
    expect(screen.queryByRole('tooltip')).toBeNull()
    expect(container.querySelector('.cross')).toBeNull()
  })

  it('hover shows the same detail at the pointer, and hides past the plot', () => {
    render(<VsLastYear progress={progress2026} />)
    // jsdom lays the 900px-wide chart out at 0,0 with no scaling: day 267 sits
    // at 48 + 267/365 × (900 − 48 − 120).
    fireEvent.mouseMove(chart(), { clientX: 48 + (267.2 / 365) * 732, clientY: 50 })
    expect(screen.getByRole('tooltip').textContent).toBe('25 Sep2026: 9,889 km2025: 8,263 km')
    fireEvent.mouseMove(chart(), { clientX: 10, clientY: 50 })
    expect(screen.queryByRole('tooltip')).toBeNull()
  })
})
