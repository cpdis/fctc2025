import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import App from './App'

// Minimal CSV that satisfies the parser's header detection (Date + Run +
// Actual kms + a +1's column) plus one real run row.
const FIXTURE_CSV = [
  'Date,Meet,Run,Approx kms,Actual kms,Alice,Bob,+1\'s',
  '"Fri, 3-Jan",Il Lido,Soft Sand,7,7.07,x,,1',
].join('\n')

function renderApp(initialEntries = ['/']) {
  return render(
    <MemoryRouter initialEntries={initialEntries}>
      <App />
    </MemoryRouter>
  )
}

describe('App', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() =>
        Promise.resolve({ ok: true, text: () => Promise.resolve(FIXTURE_CSV) })
      )
    )
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('renders the loading state without crashing', () => {
    renderApp()
    expect(screen.getByText(/Loading run data/i)).toBeInTheDocument()
  })

  it('shows an error when a per-year CSV fails to load (404)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.resolve({ ok: false, status: 404 }))
    )
    renderApp()
    expect(await screen.findByText(/Error loading data/i)).toBeInTheDocument()
  })
})
