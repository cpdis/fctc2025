import { fireEvent, render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import SiteHeader from './SiteHeader'
import SeasonTitle from './SeasonTitle'
import HeadlineNumbers from './HeadlineNumbers'
import Marquee, { streakLeaders } from './Marquee'
import SiteFooter from './SiteFooter'
import Tooltip, { tipPosition, useTooltip } from './Tooltip'
import { formatSigned } from './format'

// Headline figures for the 2026 snapshot (the mockup's data.js): 118 runs and
// 9,889 member-km against 80 runs and 8,263 km at the same date in 2025.
const TOTALS_2026 = { runs: 118, km: 9889, runners: 30, perRun: 8.23 }
const DELTA_2026 = { year: 2025, runs: 38, km: 1626 }

function renderAt(path, ui) {
  return render(<MemoryRouter initialEntries={[path]}>{ui}</MemoryRouter>)
}

// Storage that throws on every call, as Safari private mode can.
const blockStorage = () =>
  ['getItem', 'setItem'].forEach((method) =>
    vi.spyOn(Storage.prototype, method).mockImplementation(() => {
      throw new DOMException('The operation is insecure.', 'SecurityError')
    })
  )

describe('SiteHeader', () => {
  afterEach(() => {
    vi.restoreAllMocks()
    delete document.documentElement.dataset.theme
    localStorage.clear()
  })

  it('under /dashboard links to /dashboard?year=… and the hub pages by path', () => {
    renderAt('/dashboard?year=2025', <SiteHeader year={2025} />)
    const nav = screen.getByRole('navigation', { name: 'Club apps' })
    expect(within(nav).getByRole('link', { name: 'Dashboard' })).toHaveAttribute('href', '/dashboard?year=2025')
    expect(within(nav).getByRole('link', { name: 'Cup' })).toHaveAttribute('href', '/cup')
    expect(within(nav).getByRole('link', { name: 'Wrapped' })).toHaveAttribute('href', '/2025wrapped')
  })

  it('at the app root links to /?year=… and sends hub pages to fctc.fun', () => {
    renderAt('/?year=all', <SiteHeader year="all" />)
    expect(screen.getByRole('link', { name: 'Dashboard' })).toHaveAttribute('href', '/?year=all')
    expect(screen.getByRole('link', { name: 'Cup' })).toHaveAttribute('href', 'https://fctc.fun/cup')
    expect(screen.getByRole('link', { name: /FCTC/ })).toHaveAttribute('href', 'https://fctc.fun/')
  })

  it('marks the Dashboard link as the current page', () => {
    renderAt('/', <SiteHeader year={2026} />)
    expect(screen.getByRole('link', { name: 'Dashboard' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', { name: 'Cup' })).not.toHaveAttribute('aria-current')
  })

  it('the theme toggle flips data-theme and writes localStorage.theme', () => {
    renderAt('/', <SiteHeader year={2026} />)
    const toggle = screen.getByRole('button', { name: 'Toggle light/dark theme' })

    fireEvent.click(toggle)
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(localStorage.getItem('theme')).toBe('dark')

    fireEvent.click(toggle)
    expect(document.documentElement.dataset.theme).toBe('light')
    expect(localStorage.getItem('theme')).toBe('light')
  })

  it('the theme toggle starts from the theme the page already has', () => {
    // The no-flash script may have set dark from the OS before React mounts.
    document.documentElement.dataset.theme = 'dark'
    renderAt('/', <SiteHeader year={2026} />)
    fireEvent.click(screen.getByRole('button', { name: 'Toggle light/dark theme' }))
    expect(document.documentElement.dataset.theme).toBe('light')
    expect(localStorage.getItem('theme')).toBe('light')
  })

  it('the theme toggle still flips the theme and the chrome colour when storage throws', () => {
    blockStorage()
    const chrome = Object.assign(document.createElement('meta'), { name: 'theme-color', content: '#faf4e6' })
    document.head.append(chrome)
    renderAt('/', <SiteHeader year={2026} />)
    fireEvent.click(screen.getByRole('button', { name: 'Toggle light/dark theme' }))
    expect(document.documentElement.dataset.theme).toBe('dark')
    // The chrome colour is set after the save, so the handler ran to the end.
    expect(chrome.content).toBe('#1c1410')
    chrome.remove()
  })
})

describe('index.html theme bootstrap', () => {
  // The inline no-flash script, run the way the browser runs it: before the app.
  const html = readFileSync(join(import.meta.dirname, '..', '..', '..', 'index.html'), 'utf-8')
  const bootstrap = html.match(/<script>([\s\S]*?)<\/script>/)[1]
  const run = (prefersDark) => {
    vi.stubGlobal('matchMedia', (query) => ({ matches: prefersDark && query === '(prefers-color-scheme: dark)' }))
    new Function(bootstrap)()
    return document.documentElement.dataset.theme
  }

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    delete document.documentElement.dataset.theme
    localStorage.clear()
  })

  it('uses the saved theme over the OS preference', () => {
    localStorage.setItem('theme', 'light')
    expect(run(true)).toBe('light')
  })

  it.each([
    [true, 'dark'],
    [false, 'light'],
  ])('falls back to the OS preference (dark: %s) when storage throws', (prefersDark, theme) => {
    blockStorage()
    expect(run(prefersDark)).toBe(theme)
  })
})

describe('SeasonTitle', () => {
  const lastRun = { date: new Date(2026, 8, 25), location: 'MSBB', type: 'River Loop' }
  const nextRun = { date: new Date(2026, 8, 28), location: 'Drift', type: 'Intervals' }

  it('titles a season "The 2026 Season" and presses its year', () => {
    render(<SeasonTitle year={2026} onSelectYear={() => {}} />)
    expect(screen.getByRole('heading', { level: 1, name: 'The 2026 Season' })).toBeInTheDocument()
    const years = screen.getByRole('group', { name: 'Season' })
    expect(within(years).getAllByRole('button').map((b) => b.textContent)).toEqual(['2025', '2026', 'All time'])
    expect(within(years).getByRole('button', { name: '2026' })).toHaveAttribute('aria-pressed', 'true')
    expect(within(years).getByRole('button', { name: '2025' })).toHaveAttribute('aria-pressed', 'false')
  })

  it('titles the combined view "All time"', () => {
    render(<SeasonTitle year="all" onSelectYear={() => {}} />)
    expect(screen.getByRole('heading', { level: 1, name: 'All time' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'All time' })).toHaveAttribute('aria-pressed', 'true')
  })

  it('reports the chosen season, a year as a number and All time as "all"', () => {
    const onSelectYear = vi.fn()
    render(<SeasonTitle year={2026} onSelectYear={onSelectYear} />)
    fireEvent.click(screen.getByRole('button', { name: '2025' }))
    fireEvent.click(screen.getByRole('button', { name: 'All time' }))
    expect(onSelectYear.mock.calls).toEqual([[2025], ['all']])
  })

  it('shows updated, last run and next run in the meta row', () => {
    const { container } = render(
      <SeasonTitle
        year={2026}
        onSelectYear={() => {}}
        updatedAt={new Date(2026, 8, 27, 22, 42)}
        lastRun={lastRun}
        nextRun={nextRun}
      />
    )
    const items = [...container.querySelectorAll('.meta > span')].map((s) => s.textContent)
    expect(items).toEqual([
      'Updated Sun 27 Sep',
      'Last run Fri 25 Sep · MSBB River Loop',
      'Next Mon 28 Sep · Drift Intervals',
    ])
  })

  it('leaves out meta items it has no value for, and the row when it has none', () => {
    const { container, rerender } = render(<SeasonTitle year={2025} onSelectYear={() => {}} lastRun={lastRun} />)
    expect(container.querySelector('.meta').textContent).toBe('Last run Fri 25 Sep · MSBB River Loop')

    rerender(<SeasonTitle year={2025} onSelectYear={() => {}} />)
    expect(container.querySelector('.meta')).toBeNull()
  })
})

describe('HeadlineNumbers', () => {
  it('shows "+38 on this time in 2025" for the 2026 snapshot', () => {
    const { container } = render(<HeadlineNumbers {...TOTALS_2026} delta={DELTA_2026} />)
    const notes = [...container.querySelectorAll('.num .d')].map((d) => d.textContent)
    expect(notes).toEqual([
      '+38 on this time in 2025',
      '+1,626 km on 2025',
      'Came to at least one run',
      'Members, not counting +1s',
    ])
  })

  it('formats every value: separators, a km unit, one decimal per run', () => {
    const { container } = render(<HeadlineNumbers {...TOTALS_2026} delta={DELTA_2026} />)
    const values = [...container.querySelectorAll('.num .v')].map((v) => v.textContent)
    expect(values).toEqual(['118', '9,889km', '30', '8.2'])
    expect(screen.getByText('Run together')).toBeInTheDocument()
  })

  it.each([
    ['2025, the first season', { runs: 104, km: 8845, runners: 27, perRun: 8.9 }],
    ['All time', { runs: 222, km: 18734, runners: 33, perRun: 8.6 }],
  ])('shows no delta for %s', (_, totals) => {
    const { container } = render(<HeadlineNumbers {...totals} delta={null} />)
    expect(container.textContent).not.toMatch(/on this time in|km on/)
    // Runs and km have no note; runners and per run keep theirs.
    expect(container.querySelectorAll('.num .d')).toHaveLength(2)
  })

  it('signs a season behind last year with a minus, and level with ±0', () => {
    const { container } = render(
      <HeadlineNumbers {...TOTALS_2026} delta={{ year: 2025, runs: -5, km: 0 }} />
    )
    const notes = [...container.querySelectorAll('.num .d')].map((d) => d.textContent)
    expect(notes.slice(0, 2)).toEqual(['−5 on this time in 2025', '±0 km on 2025'])
  })

  it('reads a km near-tie as level, not −0', () => {
    const { container } = render(
      <HeadlineNumbers {...TOTALS_2026} delta={{ year: 2025, runs: 3, km: -0.3 }} />
    )
    expect(container.querySelectorAll('.num .d')[1].textContent).toBe('±0 km on 2025')
  })
})

describe('formatSigned', () => {
  it.each([
    [38, '+38'],
    [-5, '−5'],
    [0, '±0'],
    // Under half a unit is level either way: never "+0" or "−0".
    [0.4, '±0'],
    [-0.3, '±0'],
    [-0.5, '−1'],
    // Halves round away from zero, as the app's rounded() does.
    [1.5, '+2'],
    [-1.5, '−2'],
    [1626.4, '+1,626'],
  ])('formats %s as %s', (value, text) => {
    expect(formatSigned(value)).toBe(text)
  })
})

describe('Marquee', () => {
  // The first member in sheet order is not the streak leader.
  const streaks = [
    { name: 'Scott', current: 2 },
    { name: 'Alex 👑', current: 0 },
    { name: 'Aaron', current: 14 },
  ]

  it('names the member with the longest current streak, not the first member', () => {
    const { container } = render(<Marquee runs={118} km={9889} runners={30} streaks={streaks} />)
    const line = container.querySelector('.track span').textContent
    expect(line).toContain('118 runs • 9,889 km • 30 runners • Aaron on 14 in a row • ')
    expect(line).not.toContain('Scott on')
  })

  it('is decorative and loops two identical halves', () => {
    const { container } = render(<Marquee runs={118} km={9889} runners={30} streaks={streaks} />)
    expect(container.querySelector('.marquee')).toHaveAttribute('aria-hidden', 'true')
    const [a, b] = container.querySelectorAll('.track span')
    expect(a.textContent).toBe(b.textContent)
  })

  it('shares the lead on a tie and drops the streak fact when nobody is on one', () => {
    expect(streakLeaders([{ name: 'Kate B', current: 3 }, { name: 'Cam', current: 3 }])).toEqual({
      names: ['Kate B', 'Cam'],
      current: 3,
    })
    expect(streakLeaders([{ name: 'Cam', current: 0 }])).toBeNull()
    expect(streakLeaders([])).toBeNull()

    const { container } = render(<Marquee runs={3} km={21} runners={4} streaks={[]} />)
    expect(container.querySelector('.track span').textContent).not.toContain('in a row')
  })

  it('writes a tie as one fact', () => {
    const tie = [{ name: 'Kate B', current: 3 }, { name: 'Cam', current: 3 }]
    const { container } = render(<Marquee runs={3} km={21} runners={4} streaks={tie} />)
    expect(container.querySelector('.track span').textContent).toContain('Kate B and Cam on 3 in a row')
  })
})

describe('SiteFooter', () => {
  it('names the club and the view', () => {
    render(<SiteFooter seasonLabel="2026 Season" />)
    expect(screen.getByRole('contentinfo')).toHaveTextContent('Filament Coffee Track Club · 2026 Season')
    expect(screen.getByText('Keep running, keep caffeinating')).toBeInTheDocument()
  })
})

describe('Tooltip', () => {
  // A chart mark that shows the shared tooltip on hover and on keyboard focus.
  function Chart() {
    const { tip, show, hide } = useTooltip()
    const detail = (
      <>
        <b>Fri 25 Sep</b> · MSBB
      </>
    )
    return (
      <>
        <svg>
          <rect
            data-testid="mark"
            tabIndex={0}
            onMouseMove={(e) => show(detail, e)}
            onMouseLeave={hide}
            onFocus={(e) => show(detail, e)}
            onBlur={hide}
          />
        </svg>
        <Tooltip tip={tip} />
      </>
    )
  }

  it('places the tip beside the pointer and keeps it on screen', () => {
    expect(tipPosition({ clientX: 100, clientY: 40 }, 1440)).toEqual({ left: 114, top: 56 })
    // Near the right edge the tip moves left so its 280px box still fits.
    expect(tipPosition({ clientX: 1400, clientY: 40 }, 1440)).toEqual({ left: 1140, top: 56 })
    // A viewport narrower than the tip pins it to the left edge.
    expect(tipPosition({ clientX: 10, clientY: 0 }, 200)).toEqual({ left: 0, top: 16 })
  })

  it('anchors under the focused mark when the event has no pointer', () => {
    const currentTarget = { getBoundingClientRect: () => ({ left: 200, width: 10, bottom: 80 }) }
    expect(tipPosition({ currentTarget }, 1440)).toEqual({ left: 219, top: 96 })
  })

  it('opens on hover and on keyboard focus with the same detail, and closes after', () => {
    render(<Chart />)
    const mark = screen.getByTestId('mark')
    // Closed tips are hidden from assistive tech.
    expect(screen.queryByRole('tooltip')).toBeNull()

    fireEvent.mouseMove(mark, { clientX: 100, clientY: 40 })
    const tip = screen.getByRole('tooltip')
    expect(tip).toHaveTextContent('Fri 25 Sep · MSBB')
    expect(tip).toHaveAttribute('data-open')
    expect(tip).toHaveStyle({ left: '114px', top: '56px' })

    fireEvent.mouseLeave(mark)
    expect(screen.queryByRole('tooltip')).toBeNull()

    fireEvent.focus(mark)
    expect(screen.getByRole('tooltip')).toHaveTextContent('Fri 25 Sep · MSBB')

    fireEvent.blur(mark)
    expect(screen.queryByRole('tooltip')).toBeNull()
  })
})
