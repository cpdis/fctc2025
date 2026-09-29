import { describe, it, expect } from 'vitest'
import {
  RUN_LOG_FILTERS,
  backHref,
  dashboardBasePath,
  dashboardHref,
  findRun,
  runHref,
  yearSwitchParams,
} from './dashboardPaths'
import { LATEST_YEAR } from '../config/years'

const params = (query) => new URLSearchParams(query)

describe('dashboardBasePath', () => {
  it('is /dashboard under the hub mount, for the page and anything below it', () => {
    expect(dashboardBasePath('/dashboard')).toBe('/dashboard')
    expect(dashboardBasePath('/dashboard/')).toBe('/dashboard')
    expect(dashboardBasePath('/dashboard/run/2026-09-25-river-loop')).toBe('/dashboard')
  })

  it('is empty at the app root, and a look-alike path is not the mount', () => {
    expect(dashboardBasePath('/')).toBe('')
    expect(dashboardBasePath('/run/2026-09-25-river-loop')).toBe('')
    expect(dashboardBasePath('/dashboards')).toBe('')
    expect(dashboardBasePath('/2025wrapped')).toBe('')
  })
})

describe('dashboardHref', () => {
  it('keeps the year under either mount point', () => {
    expect(dashboardHref('/dashboard', 2025)).toBe('/dashboard?year=2025')
    expect(dashboardHref('', 'all')).toBe('/?year=all')
  })
})

describe('runHref', () => {
  it('is /dashboard/run/<id>?year=… under the hub and /run/<id>?year=… at the root', () => {
    expect(runHref('/dashboard', '2025-12-31-intervals', params('year=2025'))).toBe(
      '/dashboard/run/2025-12-31-intervals?year=2025'
    )
    expect(runHref('', '2025-12-31-intervals', params('year=all'))).toBe('/run/2025-12-31-intervals?year=all')
  })

  it('keeps the run-log filters in a fixed order and drops params outside the view', () => {
    const query = params('q=aaron&utm_source=chat&month=Jan&year=2026&location=Il+Lido&type=Drift')
    expect(runHref('', '2026-01-05-cruise', query)).toBe(
      '/run/2026-01-05-cruise?year=2026&type=Drift&location=Il+Lido&month=Jan&q=aaron'
    )
  })

  it('writes the latest season when the view has no year or a bad one', () => {
    expect(runHref('', '2026-01-05-cruise', params(''))).toBe(`/run/2026-01-05-cruise?year=${LATEST_YEAR}`)
    expect(runHref('', '2026-01-05-cruise', params('year=1999'))).toBe(`/run/2026-01-05-cruise?year=${LATEST_YEAR}`)
  })

  it('leaves out empty filters', () => {
    expect(runHref('', '2026-01-05-cruise', params('year=2026&type=&q='))).toBe('/run/2026-01-05-cruise?year=2026')
  })
})

describe('backHref', () => {
  it('returns to the view the run was opened from, filters included', () => {
    expect(backHref('/dashboard', params('year=2025&type=Drift&q=aaron'))).toBe(
      '/dashboard?year=2025&type=Drift&q=aaron'
    )
    expect(backHref('', params('year=all'))).toBe('/?year=all')
  })
})

describe('yearSwitchParams', () => {
  // Covers AE7: switching year drops type, location, month and q.
  it('drops every run-log filter and sets the new year', () => {
    const current = params('year=2026&type=Drift&location=Il+Lido&month=Jan&q=aaron')
    expect(yearSwitchParams(current, 2025).toString()).toBe('year=2025')
    expect(RUN_LOG_FILTERS).toEqual(['type', 'location', 'month', 'q'])
  })

  it('keeps params that are not filters and leaves the input untouched', () => {
    const current = params('utm_source=chat&year=2026&type=Drift')
    expect(yearSwitchParams(current, 'all').toString()).toBe('utm_source=chat&year=all')
    expect(current.toString()).toBe('utm_source=chat&year=2026&type=Drift')
  })
})

describe('findRun', () => {
  const lastRun2025 = { id: '2025-12-31-intervals' }
  const firstRun2026 = { id: '2026-01-02-soft-sand' }
  const seasons = { 2025: { runs: [lastRun2025] }, 2026: { runs: [firstRun2026] } }

  it('resolves an id inside its own season', () => {
    expect(findRun(seasons, '2025-12-31-intervals')).toBe(lastRun2025)
    expect(findRun(seasons, '2026-01-02-soft-sand')).toBe(firstRun2026)
  })

  it('returns null for an old numeric id, an unknown id or a season not loaded', () => {
    expect(findRun(seasons, '12')).toBeNull()
    expect(findRun(seasons, '2025-12-31-long-run')).toBeNull()
    expect(findRun(seasons, '2024-12-31-intervals')).toBeNull()
    expect(findRun(seasons, undefined)).toBeNull()
  })
})
