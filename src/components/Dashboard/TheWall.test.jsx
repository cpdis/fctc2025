import { fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import TheWall from './TheWall'
import { wallModel } from '../../utils/dashboardMetrics'
import { snap2025, snap2026, snapAllTime } from '../../test/snapshot'

const wall2026 = wallModel(snap2026)
const wall2025 = wallModel(snap2025)
const wallAll = wallModel(snapAllTime)

const STORAGE_KEY = 'fctc.findYourself'

const grid = () => screen.getByRole('grid', { name: 'Attendance grid: one row per runner, one column per run' })
// Plain selectors for the bulk queries: role lookups over thousands of rects are slow.
const rows = () => [...grid().querySelectorAll('[role="row"]')]
const rowNames = () => rows().map((row) => row.getAttribute('aria-label').split(':')[0])
const rowOf = (name) => rows().find((row) => row.getAttribute('aria-label').startsWith(`${name}:`))
const namesColumn = (container) => [...container.querySelectorAll('.names div')]
const sortBy = (value) => fireEvent.change(screen.getByRole('combobox', { name: 'Sort runners' }), { target: { value } })
const find = (value) => fireEvent.change(screen.getByRole('combobox', { name: 'Find a runner' }), { target: { value } })
const openTip = () => screen.getByRole('tooltip')

afterEach(() => {
  localStorage.clear()
  vi.restoreAllMocks()
})

describe('TheWall', () => {
  it('draws one row per active runner against every run, with names and totals beside the grid', () => {
    const { container } = render(<TheWall model={wall2026} />)
    expect(rows()).toHaveLength(30)
    expect(rows().every((row) => row.querySelectorAll('[role="gridcell"]').length === 118)).toBe(true)
    expect(rowNames().slice(0, 3)).toEqual(['Aaron', 'Scott', 'Alex 👑'])

    // Readable without hover: the name and "runs · current streak" on every row.
    expect(namesColumn(container)[0]).toHaveTextContent('Aaron')
    expect(container.querySelector('.tots div')).toHaveTextContent('89 · 14▲')
    expect(rowOf('Grant')).toHaveAttribute('aria-label', 'Grant: 75 runs, current streak 0')
  })

  it("colours Aaron's 14-club-day streak and bands the three specials", () => {
    render(<TheWall model={wall2026} />)
    expect(rowOf('Aaron').querySelectorAll('.cell.streak')).toHaveLength(14)
    expect(rowOf('Aaron').querySelectorAll('.cell.ran')).toHaveLength(89)
    expect(grid().querySelectorAll('.band')).toHaveLength(3)
    // A single season has nobody off the roster, so the legend leaves it out.
    expect(screen.queryByText('Not on the roster')).toBeNull()
  })

  it('sorts by current streak (Aaron first for 2026) and A–Z', () => {
    render(<TheWall model={wall2026} />)
    sortBy('streak')
    expect(rowNames().slice(0, 5)).toEqual(['Aaron', 'Cam', 'Scott', 'Kate B', 'Alex B'])
    sortBy('name')
    expect(rowNames().slice(0, 2)).toEqual(['Aaron', 'Adam'])
    sortBy('runs')
    expect(rowNames().slice(0, 2)).toEqual(['Aaron', 'Scott'])
  })

  it('lists the active runners A–Z, highlights the chosen one and dims the rest', () => {
    const { container } = render(<TheWall model={wall2026} />)
    const options = within(screen.getByRole('combobox', { name: 'Find a runner' })).getAllByRole('option')
    expect(options[0]).toHaveTextContent('Find yourself…')
    expect(options).toHaveLength(31)
    const names = options.slice(1).map((option) => option.value)
    expect(names).toEqual([...names].sort((a, b) => a.localeCompare(b, 'en')))

    find('Cam')
    expect(localStorage.getItem(STORAGE_KEY)).toBe('Cam')
    const cam = namesColumn(container).find((div) => div.textContent === 'Cam')
    expect(cam).toHaveClass('hl')
    expect(namesColumn(container).filter((div) => div.classList.contains('dim'))).toHaveLength(29)
    expect(rowOf('Cam')).not.toHaveClass('dim')
    expect(rowOf('Aaron')).toHaveClass('dim')

    find('')
    expect(localStorage.getItem(STORAGE_KEY)).toBeNull()
    expect(container.querySelectorAll('.dim')).toHaveLength(0)
  })

  it('keeps the chosen runner across a year switch while they are active in the view', () => {
    const { rerender } = render(<TheWall model={wall2026} />)
    const picker = () => screen.getByRole('combobox', { name: 'Find a runner' })

    find('Cam')
    rerender(<TheWall model={wall2025} />)
    expect(picker()).toHaveValue('Cam')

    // Deano joined in 2026: 2025 shows nobody chosen, and 2026 finds him again.
    rerender(<TheWall model={wall2026} />)
    find('Deano')
    rerender(<TheWall model={wall2025} />)
    expect(picker()).toHaveValue('')
    expect(rows().some((row) => row.classList.contains('dim'))).toBe(false)
    rerender(<TheWall model={wall2026} />)
    expect(picker()).toHaveValue('Deano')
  })

  it('reads the stored runner on load, and still works when storage throws', () => {
    localStorage.setItem(STORAGE_KEY, 'Scott')
    const { unmount } = render(<TheWall model={wall2026} />)
    expect(screen.getByRole('combobox', { name: 'Find a runner' })).toHaveValue('Scott')
    unmount()

    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('blocked')
    })
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked')
    })
    render(<TheWall model={wall2026} />)
    expect(screen.getByRole('combobox', { name: 'Find a runner' })).toHaveValue('')
    find('Cam')
    expect(rowOf('Aaron')).toHaveClass('dim')
  })

  it('opens on the latest runs on first draw and on a year switch, never on a sort or a find', () => {
    // Record every write to scrollLeft; jsdom has no layout, so scrollWidth is 0.
    const writes = []
    const native = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollLeft')
    Object.defineProperty(Element.prototype, 'scrollLeft', {
      configurable: true,
      get: native.get,
      set(value) {
        writes.push(this)
        native.set.call(this, value)
      },
    })
    try {
      const { container, rerender } = render(<TheWall model={wall2026} />)
      const scroller = container.querySelector('.wall .grid')
      expect(writes).toEqual([scroller])

      sortBy('streak')
      find('Cam')
      rerender(<TheWall model={wall2026} />)
      expect(writes).toHaveLength(1)

      rerender(<TheWall model={wall2025} />)
      expect(writes).toEqual([scroller, scroller])
    } finally {
      Object.defineProperty(Element.prototype, 'scrollLeft', native)
    }
  })

  it('a keyboard user tabs to one cell and sees the same tooltip as hovering it', () => {
    render(<TheWall model={wall2026} />)
    const tabbable = grid().querySelectorAll('[tabindex="0"]')
    // One tab stop: the top runner on the latest run.
    expect(tabbable).toHaveLength(1)
    const cell = tabbable[0]
    expect(cell).toHaveAttribute('aria-label', 'Fri 25 Sep, River Loop: Aaron ran ✓ (current streak)')

    fireEvent.focus(cell)
    const focused = openTip().textContent
    expect(openTip()).toHaveTextContent('Fri 25 Sep · MSBB')
    expect(openTip()).toHaveTextContent('River Loop · 12.4 km · 5 runners')
    expect(openTip()).toHaveTextContent('Aaron: ran ✓ (current streak)')
    fireEvent.blur(cell)
    expect(screen.queryByRole('tooltip')).toBeNull()

    // Hover the same cell by position (jsdom puts the grid at 0,0).
    fireEvent.mouseMove(grid(), {
      clientX: Number(cell.getAttribute('x')) + 1,
      clientY: Number(cell.getAttribute('y')) + 1,
    })
    expect(openTip().textContent).toBe(focused)
    fireEvent.mouseLeave(grid())
    expect(screen.queryByRole('tooltip')).toBeNull()
  })

  it('moves the tab stop with the arrow keys', () => {
    render(<TheWall model={wall2026} />)
    const start = grid().querySelector('[tabindex="0"]')
    fireEvent.focus(start)

    fireEvent.keyDown(start, { key: 'ArrowDown' })
    expect(document.activeElement).toHaveAttribute('data-r', '1')
    expect(document.activeElement).toHaveAttribute('data-c', '117')
    fireEvent.keyDown(document.activeElement, { key: 'ArrowLeft' })
    expect(document.activeElement).toHaveAttribute('data-c', '116')
    fireEvent.keyDown(document.activeElement, { key: 'Home' })
    expect(document.activeElement).toHaveAttribute('data-c', '0')
    expect(document.activeElement).toHaveAttribute('tabindex', '0')
    expect(grid().querySelectorAll('[tabindex="0"]')).toHaveLength(1)
    expect(openTip()).toHaveTextContent('Scott:')
  })

  it('shows All time runners who were not on a season’s sheet as not on the roster', () => {
    render(<TheWall model={wallAll} />)
    expect(screen.getByText('Not on the roster')).toBeInTheDocument()
    const deano = rowOf('Deano')
    const first = deano.querySelector('[data-c="0"]')
    expect(first).toHaveClass('off')
    expect(first.getAttribute('aria-label')).toMatch(/Deano not on the roster$/)
    fireEvent.focus(first)
    expect(openTip()).toHaveTextContent('Deano: not on the roster')
    expect(openTip()).not.toHaveTextContent('missed')
    // Months carry the year when the view spans seasons.
    expect(within(grid()).getByText('JAN ’25')).toBeInTheDocument()
    expect(within(grid()).getByText('JAN ’26')).toBeInTheDocument()
  })

  it('says so when the view has no runs yet', () => {
    render(<TheWall model={{ columns: [], rows: [] }} />)
    expect(screen.getByText('No runs yet.')).toBeInTheDocument()
    expect(screen.queryByRole('grid')).toBeNull()
  })
})
