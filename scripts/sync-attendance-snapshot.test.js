// @vitest-environment node
import { describe, it, expect } from 'vitest'
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { createHash } from 'node:crypto'
import { validateSnapshot, serializeCSV, syncAttendanceSnapshot } from './sync-attendance-snapshot.js'

function snapshot() {
  const value = { ok: true, apiVersion: 2, spreadsheetId: 'test-workbook', capturedAt: '2026-09-16T08:00:00.000Z',
    seasons: [2025, 2026].map(year => ({ year, seasonSheetId: year, title: String(year), grid: [
      ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', 'Col', 'Rene', "+1's", 'Total'],
      ['Fri, 3-Jan', 'Beach, "north"\nMeet here', 'Soft Sand', '7.5', '7.2', 'x', 'x', '0', '2'],
    ] })) }
  value.snapshotRevision = digest(value)
  return value
}
function digest(value) {
  return createHash('sha256').update(JSON.stringify({ spreadsheetId: value.spreadsheetId, seasons: value.seasons })).digest('hex')
}
function directory() {
  const root = mkdtempSync(join(tmpdir(), 'fctc-snapshot-test-'))
  mkdirSync(join(root, 'public/data'), { recursive: true })
  for (const year of [2025, 2026]) writeFileSync(join(root, `public/data/${year}.csv`), 'original ' + year)
  writeFileSync(join(root, 'public/data/last-updated.json'), '{"updatedAt":"before"}\n')
  return root
}
const response = value => ({ ok: true, status: 200, text: async () => JSON.stringify(value) })
const options = root => ({ root, endpoint: 'https://script.google.com/macros/s/test/exec', secret: 'private-test-secret' })

describe('consistent attendance snapshot sync', () => {
  it('serializes quoted fields, embedded newlines, dates and empty cells without changing values', () => {
    expect(serializeCSV([['Fri, 3-Jan', 'a"b', 'a\nb', '', '7.2']])).toBe('"Fri, 3-Jan","a""b","a\nb",,7.2\r\n')
    expect(validateSnapshot(snapshot()).map(s => s.year)).toEqual([2025, 2026])
  })

  it('rejects missing, duplicate, extra, corrupt and oversized seasons', () => {
    for (const edit of [
      s => { s.seasons.pop() },
      s => { s.seasons[1] = structuredClone(s.seasons[0]) },
      s => { s.seasons[0].year = 2024 },
      s => { s.seasons[0].grid[0][0] = 'Private history' },
      s => { s.seasons[0].grid[1][0] = 2025 },
      s => { s.seasons[0].grid[1][1] = 'x'.repeat(1_300_000) },
    ]) {
      const value = snapshot(); edit(value); value.snapshotRevision = digest(value)
      expect(() => validateSnapshot(value)).toThrow()
    }
    const tampered = snapshot(); tampered.seasons[0].grid[1][5] = ''
    expect(() => validateSnapshot(tampered)).toThrow(/revision/i)
  })

  it('validates every season before replacing either CSV or the timestamp', async () => {
    const root = directory(), value = snapshot()
    value.seasons[1].grid = [['invalid']]; value.snapshotRevision = digest(value)
    await expect(syncAttendanceSnapshot({ ...options(root), fetchImpl: async () => response(value) })).rejects.toThrow()
    for (const year of [2025, 2026]) expect(readFileSync(join(root, `public/data/${year}.csv`), 'utf8')).toBe('original ' + year)
    expect(readFileSync(join(root, 'public/data/last-updated.json'), 'utf8')).toBe('{"updatedAt":"before"}\n')
  })

  it('writes both validated years and leaves the timestamp untouched on a no-op', async () => {
    const root = directory(), value = snapshot(), requests = []
    const fetchImpl = async (url, request) => { requests.push([url, JSON.parse(request.body)]); return response(value) }
    const first = await syncAttendanceSnapshot({ ...options(root), fetchImpl, now: () => new Date('2026-09-16T09:00:00Z') })
    expect(first.changedYears).toEqual([2025, 2026])
    expect(requests[0][1]).toEqual({ action: 'exportAttendanceSnapshot', secret: 'private-test-secret' })
    const timestamp = readFileSync(join(root, 'public/data/last-updated.json'), 'utf8')
    const second = await syncAttendanceSnapshot({ ...options(root), fetchImpl, now: () => new Date('2026-09-17T09:00:00Z') })
    expect(second.changedYears).toEqual([])
    expect(readFileSync(join(root, 'public/data/last-updated.json'), 'utf8')).toBe(timestamp)
    expect(existsSync(join(root, 'public/data/_FCTC_Guests.csv'))).toBe(false)
    expect(JSON.stringify(first)).not.toContain('private-test-secret')
  })

  it('fails on busy, authentication and HTML responses without writing any data', async () => {
    for (const result of [response({ ok: false, error: 'busy' }), response({ ok: false, error: 'bad_secret' }),
      { ok: true, status: 200, text: async () => '<html>Sign in</html>' }]) {
      const root = directory()
      await expect(syncAttendanceSnapshot({ ...options(root), fetchImpl: async () => result })).rejects.toThrow()
      expect(readFileSync(join(root, 'public/data/2025.csv'), 'utf8')).toBe('original 2025')
      expect(readFileSync(join(root, 'public/data/2026.csv'), 'utf8')).toBe('original 2026')
    }
  })
})
