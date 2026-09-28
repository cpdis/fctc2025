import { fireEvent, render, screen, within } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import App from './App'
import { YEARS } from './config/years'

// The dated snapshot (2026-09-27): 2025 runs to Wed 31 Dec, 2026 to Fri 25 Sep.
// Under jsdom import.meta.url is not a file: URL; use import.meta.dirname.
const snapshotDir = join(import.meta.dirname, '..', 'fixtures', 'attendance', '2026-09-27')
const CSV_BY_URL = Object.fromEntries(
  Object.entries(YEARS).map(([year, url]) => [url, readFileSync(join(snapshotDir, `${year}.csv`), 'utf-8')])
)

// Serve each season's CSV by URL; `failing` answers 404 instead.
function stubFetch({ failing } = {}) {
  const fetch = vi.fn((url) =>
    Promise.resolve(
      url === failing ? { ok: false, status: 404 } : { ok: true, text: () => Promise.resolve(CSV_BY_URL[url]) }
    )
  )
  vi.stubGlobal('fetch', fetch)
  return fetch
}

// Shows the router's current URL, so tests can read what a click navigated to.
function LocationProbe() {
  const { pathname, search } = useLocation()
  return <output data-testid="location">{pathname + search}</output>
}

function renderApp(path = '/') {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <App />
      <LocationProbe />
    </MemoryRouter>
  )
}

const currentUrl = () => screen.getByTestId('location').textContent

describe('App', () => {
  let fetch

  beforeEach(() => {
    fetch = stubFetch()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('shows the loading state until every season has loaded', async () => {
    renderApp('/run/2025-12-31-intervals?year=2025')
    expect(screen.getByText(/Loading run data/i)).toBeInTheDocument()
    expect(await screen.findByRole('heading', { level: 1, name: 'Wed 31 Dec 2025' })).toBeInTheDocument()
    expect(screen.queryByText(/Loading run data/i)).not.toBeInTheDocument()
  })

  it('shows the error screen when one season fails to load', async () => {
    stubFetch({ failing: YEARS[2026] })
    renderApp()
    expect(await screen.findByText(/Error loading data/i)).toBeInTheDocument()
    expect(screen.getByText('Failed to load 2026 data (HTTP 404)')).toBeInTheDocument()
  })

  it('loads every season again when Try again follows a failed load', async () => {
    // 2026 fails once (a dropped connection, a CDN blip), then serves its CSV.
    stubFetch({ failing: YEARS[2026] })
    renderApp('/?year=2026')
    const tryAgain = await screen.findByRole('button', { name: 'Try again' })

    const refetch = stubFetch()
    fireEvent.click(tryAgain)
    expect(screen.getByText(/Loading run data/i)).toBeInTheDocument()
    expect(await screen.findByRole('heading', { level: 1, name: 'The 2026 Season' })).toBeInTheDocument()
    expect(screen.queryByText(/Error loading data/i)).not.toBeInTheDocument()
    // Every season again (the dashboard also asks for last-updated.json).
    expect(refetch.mock.calls.map(([url]) => url)).toEqual(expect.arrayContaining(Object.values(YEARS)))
  })

  it('stays on the error screen when the retry fails too', async () => {
    const failing = stubFetch({ failing: YEARS[2025] })
    renderApp()
    fireEvent.click(await screen.findByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Failed to load 2025 data (HTTP 404)')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument()
    // Two full loads: the first one and the retry.
    expect(failing).toHaveBeenCalledTimes(2 * Object.keys(YEARS).length)
  })

  it('fetches every season exactly once and serves Wrapped 2025 from the same store', async () => {
    renderApp('/2025wrapped')
    // 2025 members only: Deano joined in 2026.
    expect(await screen.findByText('Alex 👑')).toBeInTheDocument()
    expect(screen.queryByText('Deano')).not.toBeInTheDocument()
    expect(fetch.mock.calls.map(([url]) => url).sort()).toEqual(Object.values(YEARS).sort())
  })

  // The fctc.fun proxy keeps /dashboard in the browser URL (finding 13).
  it('routes a fresh /dashboard/run/<id> link to the run in its own season', async () => {
    renderApp('/dashboard/run/2025-12-31-intervals?year=all')
    expect(await screen.findByRole('heading', { level: 1, name: 'Wed 31 Dec 2025' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to All Time' })).toHaveAttribute('href', '/dashboard?year=all')
  })

  // Covers AE6 end to end: a row click in the dashboard opens that exact run
  // and keeps the selected year, under either mount point.
  it('opens the 31 Dec 2025 row from the 2025 view', async () => {
    renderApp('/?year=2025')
    fireEvent.click(await screen.findByRole('cell', { name: 'Wed 31 Dec' }))
    expect(currentUrl()).toBe('/run/2025-12-31-intervals?year=2025')
    expect(screen.getByRole('heading', { level: 1, name: 'Wed 31 Dec 2025' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to 2025 Season' })).toBeInTheDocument()
  })

  it('opens a 2025 row from the All time view under /dashboard', async () => {
    renderApp('/dashboard?year=all')
    fireEvent.click(await screen.findByRole('button', { name: /^Show all \d+ runs$/ }))
    fireEvent.click(screen.getByRole('cell', { name: 'Wed 31 Dec 2025' }))
    expect(currentUrl()).toBe('/dashboard/run/2025-12-31-intervals?year=all')
    expect(screen.getByRole('heading', { level: 1, name: 'Wed 31 Dec 2025' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to All Time' })).toBeInTheDocument()
  })

  // Covers AE7: a year switch in the title band drops every run-log filter.
  it('drops the run-log filters when the title band switches year', async () => {
    renderApp('/dashboard?year=2026&type=Drift&location=Drift&month=Jan&q=aaron')
    const seasons = await screen.findByRole('group', { name: 'Season' })
    fireEvent.click(within(seasons).getByRole('button', { name: '2025' }))
    expect(currentUrl()).toBe('/dashboard?year=2025')
    expect(screen.getByRole('heading', { level: 1, name: 'The 2025 Season' })).toBeInTheDocument()
  })
})
