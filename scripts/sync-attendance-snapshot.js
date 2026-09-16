#!/usr/bin/env node
import { createHash } from 'node:crypto'
import { mkdtemp, mkdir, readFile, writeFile, rename, rm } from 'node:fs/promises'
import { resolve, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import SheetOps from '../apps-script/SheetOps.js'
import { YEARS } from '../src/config/years.js'

const SUPPORTED_YEARS = Object.keys(YEARS).map(Number).sort()
const MAX_BYTES = 5_000_000
const MAX_CELLS = 250_000
const MAX_CHARACTERS = 1_200_000

export function serializeCSV(grid) {
  return grid.map(row => row.map(value => /[",\r\n]/.test(value)
    ? '"' + value.replaceAll('"', '""') + '"' : value).join(',')).join('\r\n') + '\r\n'
}

/** Reject the complete capture before creating any replacement dataset. */
export function validateSnapshot(snapshot) {
  if (!snapshot || snapshot.ok !== true || snapshot.apiVersion !== 2 ||
      typeof snapshot.spreadsheetId !== 'string' || !snapshot.spreadsheetId ||
      typeof snapshot.capturedAt !== 'string' || !Number.isFinite(Date.parse(snapshot.capturedAt)) ||
      !/^[a-f0-9]{64}$/.test(snapshot.snapshotRevision) || !Array.isArray(snapshot.seasons)) {
    throw new Error('Invalid attendance snapshot envelope.')
  }
  if (Buffer.byteLength(JSON.stringify(snapshot)) > MAX_BYTES) throw new Error('Attendance snapshot is too large.')
  const years = snapshot.seasons.map(season => season?.year)
  if (years.length !== SUPPORTED_YEARS.length || new Set(years).size !== years.length ||
      [...years].sort().some((year, index) => year !== SUPPORTED_YEARS[index])) {
    throw new Error('The snapshot must contain every supported season exactly once.')
  }
  let cells = 0
  const seasons = snapshot.seasons.map(season => {
    if (!Number.isSafeInteger(season.seasonSheetId) || season.seasonSheetId < 0 || season.title !== String(season.year) ||
        !Array.isArray(season.grid) || !season.grid.length || !Array.isArray(season.grid[0])) {
      throw new Error('Invalid season identity or grid.')
    }
    const width = season.grid[0].length
    if (!width || season.grid.some(row => !Array.isArray(row) || row.length !== width || row.some(value => typeof value !== 'string'))) {
      throw new Error('A season must contain a rectangular grid of displayed strings.')
    }
    cells += season.grid.length * width
    if (cells > MAX_CELLS) throw new Error('Attendance snapshot has too many cells.')
    const geometry = SheetOps.sheetGeometry(season.grid)
    if (!geometry || !geometry.band.length || !SheetOps.listRuns(season.grid, geometry.headerRow).length) {
      throw new Error('A season has no valid attendance header or runs.')
    }
    // Rebuild the precise server field order for its content digest. Never
    // serialize auxiliary records or accept remote filenames as output paths.
    return { year: season.year, seasonSheetId: season.seasonSheetId, title: season.title, grid: season.grid }
  })
  const content = JSON.stringify({ spreadsheetId: snapshot.spreadsheetId, seasons })
  if (content.length > MAX_CHARACTERS) throw new Error('Attendance snapshot is too large.')
  const revision = createHash('sha256').update(content).digest('hex')
  if (revision !== snapshot.snapshotRevision) throw new Error('Attendance snapshot revision does not match its contents.')
  return seasons.sort((a, b) => a.year - b.year)
}

async function existingFile(path) {
  try { return await readFile(path, 'utf8') } catch (error) {
    if (error.code === 'ENOENT') return null
    throw error
  }
}

/** Stage every file first. Roll back adopted files if a local replacement fails. */
async function replaceDataset(directory, replacements) {
  await mkdir(directory, { recursive: true })
  const stage = await mkdtemp(join(directory, '.snapshot-'))
  const applied = []
  try {
    for (const item of replacements) await writeFile(join(stage, item.name), item.content, 'utf8')
    for (const item of replacements) {
      await rename(join(stage, item.name), join(directory, item.name))
      applied.push(item)
    }
  } catch (error) {
    const failures = []
    for (const item of applied.reverse()) {
      try {
        if (item.previous === null) await rm(join(directory, item.name))
        else await writeFile(join(directory, item.name), item.previous, 'utf8')
      } catch (rollbackError) { failures.push(rollbackError) }
    }
    if (failures.length) throw new AggregateError([error, ...failures], 'Snapshot replacement failed; local recovery is required. No commit was made.')
    throw error
  } finally { await rm(stage, { recursive: true, force: true }) }
}

export async function syncAttendanceSnapshot({ root = resolve(import.meta.dirname, '..'), endpoint, secret,
  fetchImpl = globalThis.fetch, now = () => new Date() } = {}) {
  let url
  try { url = new URL(endpoint) } catch { throw new Error('Set FCTC_ATTENDANCE_ENDPOINT to the Apps Script web app URL.') }
  if (url.protocol !== 'https:' || url.hostname !== 'script.google.com' || url.username || url.password || url.search || url.hash ||
      !/^\/macros\/s\/[^/]+\/exec$/.test(url.pathname)) throw new Error('Use the HTTPS Apps Script /exec endpoint without query parameters.')
  if (typeof secret !== 'string' || !secret.trim()) throw new Error('Set FCTC_ATTENDANCE_SECRET before syncing attendance.')
  let response
  try {
    response = await fetchImpl(url.href, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'exportAttendanceSnapshot', secret }), signal: AbortSignal.timeout(60_000) })
  } catch { throw new Error('Attendance snapshot request failed. No data changed.') }
  if (!response.ok) throw new Error('Attendance snapshot request returned an HTTP error. No data changed.')
  const body = await response.text()
  if (Buffer.byteLength(body) > MAX_BYTES) throw new Error('Attendance snapshot response is too large.')
  let snapshot
  try { snapshot = JSON.parse(body) } catch { throw new Error('Attendance endpoint did not return JSON. Check deployment and permissions.') }
  if (snapshot?.ok === false) {
    // Do not echo remote messages, request bodies, or credentials into CI logs.
    const reason = ['busy', 'bad_secret', 'snapshot_invalid', 'snapshot_too_large', 'shared_guests_disabled'].includes(snapshot.error)
      ? snapshot.error : 'service_error'
    throw new Error(`Attendance snapshot unavailable (${reason}). No data changed.`)
  }
  const seasons = validateSnapshot(snapshot), directory = join(root, 'public/data'), replacements = [], changedYears = []
  for (const season of seasons) {
    const name = `${season.year}.csv`, content = serializeCSV(season.grid), previous = await existingFile(join(directory, name))
    if (content !== previous) { replacements.push({ name, content, previous }); changedYears.push(season.year) }
  }
  if (!replacements.length) return { changedYears, snapshotRevision: snapshot.snapshotRevision }
  const name = 'last-updated.json'
  replacements.push({ name, content: JSON.stringify({ updatedAt: now().toISOString() }, null, 2) + '\n',
    previous: await existingFile(join(directory, name)) })
  await replaceDataset(directory, replacements)
  return { changedYears, snapshotRevision: snapshot.snapshotRevision }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  syncAttendanceSnapshot({ endpoint: process.env.FCTC_ATTENDANCE_ENDPOINT, secret: process.env.FCTC_ATTENDANCE_SECRET })
    .then(result => console.log(result.changedYears.length
      ? `Updated attendance seasons: ${result.changedYears.join(', ')}` : 'Attendance is unchanged; no timestamp update.'))
    .catch(error => { console.error(error.message); process.exitCode = 1 })
}
