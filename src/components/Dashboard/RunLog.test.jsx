import { describe, it, expect } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes, useLocation, useSearchParams } from 'react-router-dom'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { combineYearData, parseRunData } from '../../utils/dataParser'
import { headline } from '../../utils/dashboardMetrics'
import { findRun, yearSwitchParams } from '../../utils/dashboardPaths'
import RunDetail from '../../pages/RunDetail'
import RunLog from './RunLog'

// The dated snapshot (2026-09-27): 2025 has 111 runs to Wed 31 Dec, 2026 has
// 118 to Fri 25 Sep. Under jsdom import.meta.url is not a file: URL.
const snapshotDir = join(import.meta.dirname, '..', '..', '..', 'fixtures', 'attendance', '2026-09-27')
const season = (year) => parseRunData(readFileSync(join(snapshotDir, `${year}.csv`), 'utf-8'), year)
const seasons = { 2025: season(2025), 2026: season(2026) }
const views = { 2025: seasons[2025], 2026: seasons[2026], all: combineYearData([seasons[2026], seasons[2025]]) }

// A dashboard stand-in: the view from ?year, the log, and a year switch that
// drops the filters the way the title band's year control does.
function LogPage() {
  const [params, setParams] = useSearchParams()
  const view = views[params.get('year') ?? 2026]
  return (
    <>
      <button type="button" onClick={() => setParams(yearSwitchParams(params, 2025))}>
        Switch to 2025
      </button>
      <RunLog runs={view.runs} />
    </>
  )
}

// Shows the router's current URL, so tests can read what a change wrote.
function LocationProbe() {
  const { pathname, search } = useLocation()
  return <output data-testid="location">{pathname + search}</output>
}

// Both mount points, with the run page, as App routes them.
function renderLog(path) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/" element={<LogPage />} />
        <Route path="/dashboard" element={<LogPage />} />
        <Route path="/run/:runId" element={<RunDetail seasons={seasons} />} />
        <Route path="/dashboard/run/:runId" element={<RunDetail seasons={seasons} />} />
      </Routes>
      <LocationProbe />
    </MemoryRouter>
  )
}

const currentUrl = () => screen.getByTestId('location').textContent
const bodyRows = () => within(screen.getByRole('table')).getAllByRole('row').slice(1)
const column = (index) => bodyRows().map((row) => within(row).getAllByRole('cell')[index].textContent)
const dates = () => column(0)
const select = (name) => screen.getByRole('combobox', { name })
const choose = (name, value) => fireEvent.change(select(name), { target: { value } })
const searchBox = () => screen.getByRole('searchbox', { name: 'Search runs or runners' })
const search = (text) => fireEvent.change(searchBox(), { target: { value: text } })
const showAll = (total) => fireEvent.click(screen.getByRole('button', { name: `Show all ${total} runs` }))
const ranBy = (year, name) => seasons[year].runs.filter((run) => run.attendees.includes(name)).length

describe('RunLog', () => {
  it('lists the view newest first, 10 rows until "Show all N runs"', () => {
    renderLog('/?year=2026')
    expect(dates()).toHaveLength(10)
    expect(dates()[0]).toBe('Fri 25 Sep')

    showAll(118)
    expect(dates()).toHaveLength(118)
    expect(dates().at(-1)).toBe('Fri 2 Jan')
    fireEvent.click(screen.getByRole('button', { name: 'Show fewer' }))
    expect(dates()).toHaveLength(10)
  })

  // Covers AE7 and review finding 8.
  it('filters to Drift in 2026, leaves the headline alone, and resets on a year switch', () => {
    const before = headline(seasons[2026], seasons[2025])
    const order = seasons[2026].runs.map((run) => run.id)
    renderLog('/?year=2026')

    choose('Location', 'Drift')
    expect(currentUrl()).toBe('/?year=2026&location=Drift')
    showAll(37)
    expect(new Set(column(2))).toEqual(new Set(['Drift']))

    // The log sorts and filters a copy: the view and its headline are untouched.
    expect(headline(seasons[2026], seasons[2025])).toEqual(before)
    expect(seasons[2026].runs.map((run) => run.id)).toEqual(order)

    fireEvent.click(screen.getByRole('button', { name: 'Switch to 2025' }))
    expect(currentUrl()).toBe('/?year=2025')
    expect(select('Location')).toHaveValue('')
    expect(screen.getByRole('button', { name: 'Show all 111 runs' })).toBeInTheDocument()
  })

  it('searches runner names, ignoring case and accents', () => {
    renderLog('/?year=2026')
    search('AARON')
    expect(currentUrl()).toBe('/?year=2026&q=AARON')
    expect(screen.getByRole('button', { name: `Show all ${ranBy(2026, 'Aaron')} runs` })).toBeInTheDocument()

    // René joined in 2026.
    search('rene')
    expect(bodyRows()).toHaveLength(Math.min(10, ranBy(2026, 'René')))
  })

  it('searches type, event, location and the date as shown, every word matching', () => {
    renderLog('/?year=2026')
    search('pub run')
    expect(dates()).toEqual(['Sat 5 Sep'])

    search('25 sep')
    expect(dates()).toEqual(['Fri 25 Sep'])

    search('drift intervals')
    expect(bodyRows().length).toBeGreaterThan(0)
    for (const row of bodyRows()) {
      expect(row).toHaveTextContent('Intervals')
      expect(row).toHaveTextContent('Drift')
    }

    fireEvent.click(screen.getByRole('button', { name: 'Switch to 2025' }))
    search('xmas')
    expect(dates()).toEqual(['Sun 14 Dec', 'Sun 14 Dec', 'Sun 14 Dec'])
  })

  it("filters by month; All time's months and dates carry the year", () => {
    const { unmount } = renderLog('/?year=2026')
    const options = () => within(select('Month')).getAllByRole('option').map((option) => option.textContent)
    expect(options()).toEqual(['All months', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep'])
    choose('Month', '2026-09')
    expect(currentUrl()).toBe('/?year=2026&month=2026-09')
    expect(dates().every((date) => date.endsWith(' Sep'))).toBe(true)
    unmount()

    renderLog('/?year=all')
    expect(options()[1]).toBe('Jan 2025')
    expect(options().at(-1)).toBe('Sep 2026')
    expect(dates()[0]).toBe('Fri 25 Sep 2026')
    choose('Month', '2025-12')
    expect(dates()[0]).toBe('Wed 31 Dec 2025')
    expect(screen.getByRole('link', { name: 'Wed 31 Dec 2025' })).toBeInTheDocument()
  })

  it('tags specials gold: off the club weekdays, or a named event', () => {
    const { unmount } = renderLog('/?year=2026')
    const tag = (type) => within(bodyRows()[0]).getByText(type)
    expect(tag('River Loop')).not.toHaveClass('sp') // Fri 25 Sep, a club run
    search('pub run')
    expect(tag('Pub Run')).toHaveClass('tag', 'sp') // a Saturday
    search('26 jan invasion')
    expect(tag('Half Marathon')).toHaveClass('sp') // a club Monday, but an event
    unmount()

    // 2025 had no official Monday run, so its Invasion Day Monday is a special.
    renderLog('/?year=2025&month=2025-01&q=27+jan')
    expect(tag('Half Marathon')).toHaveClass('sp')
  })

  it('shows "—" for a run with no km, never "0"', () => {
    const csv = [
      "Date,Meet,Run,Approx kms,Actual kms,Alice,Bob,+1's",
      '"Wed, 7-Jan",Drift,Intervals,,,x,x,1',
    ].join('\n')
    render(
      <MemoryRouter>
        <RunLog runs={parseRunData(csv, 2026).runs} />
      </MemoryRouter>
    )
    const [date, , where, km, runners] = within(bodyRows()[0]).getAllByRole('cell')
    expect(date).toHaveTextContent('Wed 7 Jan')
    expect(where).toHaveTextContent('Drift')
    expect(km).toHaveTextContent('—')
    // Two member dots and one hollow +1 dot, then the count.
    expect(runners.querySelectorAll('.dots i')).toHaveLength(3)
    expect(runners.querySelectorAll('.dots i.g')).toHaveLength(1)
    expect(runners).toHaveTextContent('3')
  })

  it('links each row to its run with the view and filters; a click anywhere on the row opens it', () => {
    renderLog('/dashboard?year=2026&location=Drift')
    const [first] = bodyRows()
    const link = within(first).getByRole('link')
    const href = link.getAttribute('href')
    expect(href).toMatch(/^\/dashboard\/run\/2026-\d{2}-\d{2}-[a-z0-9-]+\?year=2026&location=Drift$/)

    fireEvent.click(within(first).getAllByRole('cell')[3])
    expect(currentUrl()).toBe(href)
    expect(screen.getByRole('heading', { level: 1, name: new RegExp(`^${link.textContent} 2026$`) })).toBeInTheDocument()
  })

  it('restores the same filters on Back from a run', () => {
    renderLog('/dashboard?year=2026')
    choose('Location', 'Drift')
    search('aaron')
    const filteredDates = dates()

    fireEvent.click(within(bodyRows()[0]).getByRole('link'))
    fireEvent.click(screen.getByRole('link', { name: 'Back to 2026 Season' }))

    expect(currentUrl()).toBe('/dashboard?year=2026&location=Drift&q=aaron')
    expect(select('Location')).toHaveValue('Drift')
    expect(searchBox()).toHaveValue('aaron')
    expect(dates()).toEqual(filteredDates)
  })

  it('shows the empty state when nothing matches, and clears the filters from it', () => {
    renderLog('/?year=2026&location=Drift&q=zzz')
    expect(screen.getByText('No runs match your filters')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Clear filters' }))
    expect(currentUrl()).toBe('/?year=2026')
    expect(searchBox()).toHaveValue('')
    expect(select('Location')).toHaveValue('')
    expect(dates()).toHaveLength(10)
  })

  it('says so when the view has no runs yet, with nothing to clear', () => {
    render(
      <MemoryRouter>
        <RunLog runs={[]} />
      </MemoryRouter>
    )
    expect(screen.getByText('No runs logged yet')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Clear filters' })).not.toBeInTheDocument()
  })

  it('ignores a filter the view does not offer', () => {
    // Drift is a 2026 location; 2025 never ran there.
    renderLog('/?year=2025&location=Drift&month=2026-01')
    expect(select('Location')).toHaveValue('')
    expect(select('Month')).toHaveValue('')
    expect(screen.getByRole('button', { name: 'Show all 111 runs' })).toBeInTheDocument()
  })

  // U9 verification: every row in both seasons, and in All time, opens its own run.
  it.each(['2025', '2026', 'all'])('links every row of the %s view to its own run', (year) => {
    renderLog(`/?year=${year}`)
    const runs = views[year].runs
    showAll(runs.length)
    const ids = bodyRows().map((row) => {
      const [path, query] = within(row).getByRole('link').getAttribute('href').split('?')
      expect(query).toBe(`year=${year}`)
      return decodeURIComponent(path.replace('/run/', ''))
    })
    expect(new Set(ids).size).toBe(runs.length)
    for (const id of ids) expect(findRun(seasons, id)?.id).toBe(id)
  })
})
