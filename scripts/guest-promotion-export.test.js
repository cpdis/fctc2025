// @vitest-environment node
// Exercise the production router, export client, dashboard parser and digest loader
// together. The Sheets fake cannot prove Google's formula recalculation behavior.
import { createHash, randomUUID } from 'node:crypto'
import { createRequire } from 'node:module'
import { readFile, mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { expect, it } from 'vitest'
import { serializeCSV, syncAttendanceSnapshot } from './sync-attendance-snapshot.js'
import { parseRunData, combineYearData } from '../src/utils/dataParser.js'
import { findUpcomingMilestones, getAttendanceCutoff } from '../src/utils/milestones.js'
import { calculateWeightedAttendanceRate } from '../src/utils/milestoneForecast.js'
import { loadAllTimeData } from './send-milestone-digest.js'
const require = createRequire(import.meta.url)
const { createEnvironment } = require('../apps-script/test/support/fakeAppsScript.js')
const GuestOps = require('../apps-script/GuestOps.js')
const contract = require('../fixtures/attendance/guests/contract.json')

function grid(year) {
  const leading = Array.from({ length: year === 2025 ? 9 : 10 }, () => [])
  return [...leading,
    ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', 'Col', 'Toby', "+1's", 'Total Attendance per run'],
    ...contract.runs.filter(run => run.seasonYear === year).map(run =>
      [run.date, 'Beach, "north"\nMeeting point', run.run, 7.5, 7.2, 'x', 'x', 1, 3])]
}
function mutate(env, action, fields) {
  const request = { apiVersion: 2, operationId: randomUUID(), action, ...fields }
  request.requestDigest = createHash('sha256').update(GuestOps.canonicalRequest(request)).digest('hex')
  const result = env.post(request)
  expect(result.status, JSON.stringify(result)).toBe('completed')
  return result
}
function parsed(snapshot) {
  return combineYearData(snapshot.seasons.map(season => parseRunData(serializeCSV(season.grid), season.year)))
}

it('eleven promoted runs flow through both season CSVs, dashboard and milestone input', async () => {
  const env = createEnvironment({ grid: grid(2026), sheetName: '2026', sheetId: 26,
    extraSheets: [{ name: '2025', sheetId: 25, grid: grid(2025) }],
    properties: { SHARED_GUESTS_SETUP_ALLOWED: 'true' } })
  mutate(env, 'setupSharedGuests', { spreadsheetId: env.spreadsheet.getId(), seasonSheetIds: [25, 26] })
  env.properties.SHARED_GUESTS_ENABLED = 'true'
  const guestId = contract.guests[0].guestId
  mutate(env, 'createGuest', { guestId, displayName: 'Rene', confirmDistinct: false })
  const entries = [25, 26].flatMap(seasonSheetId => {
    const state = env.post({ action: 'getState', apiVersion: 2, seasonSheetId })
    return state.runs.map(run => ({ spreadsheetId: state.spreadsheetId, seasonSheetId,
      runId: run.runId, expectedDate: run.date, expectedRun: run.run, assignment: 'existing_unnamed_slot' }))
  })
  const imported = env.post({ action: 'previewGuestImport', guestId, entries })
  mutate(env, 'importGuestHistory', { guestId, entries: imported.entries,
    baseGuestRevision: imported.baseGuestRevision, baseRevision: imported.baseRevision })
  const before = parsed(env.post({ action: 'exportAttendanceSnapshot' }))
  const preview = env.post({ action: 'previewPromotion', guestId, memberName: 'Rene', targetMode: 'create' })
  expect(preview.confirmedRuns).toBe(11)
  mutate(env, 'commitPromotion', { guestId, memberName: 'Rene', targetMode: 'create', previewToken: preview.previewToken })
  const snapshot = env.post({ action: 'exportAttendanceSnapshot' })
  const after = parsed(snapshot)
  expect(after.memberTotals.Rene.totalRuns).toBe(11)
  expect(after.memberTotals.Rene.totalKm).toBeCloseTo(79.2)
  expect(after.leaderboard.find(member => member.name === 'Rene').totalRuns).toBe(11)
  expect(after.runs.map(run => [run.date, run.runType, run.actualKm, run.totalAttendance, run.aggregateKm]))
    .toEqual(before.runs.map(run => [run.date, run.runType, run.actualKm, run.totalAttendance, run.aggregateKm]))
  expect(after.memberTotals.Col).toEqual(before.memberTotals.Col)
  expect(after.memberTotals.Toby).toEqual(before.memberTotals.Toby)
  expect(after.runs.every(run => run.plusOnes === 0 && run.attendance.Rene)).toBe(true)
  expect(snapshot.seasons.map(season => parseRunData(serializeCSV(season.grid), season.year).memberTotals.Rene.totalRuns)).toEqual([3, 8])
  expect(calculateWeightedAttendanceRate(after.runs.map(run => Boolean(run.attendance.Rene)))).toBe(1)

  const root = await mkdtemp(join(tmpdir(), 'fctc-promotion-export-'))
  try {
    const result = await syncAttendanceSnapshot({ root, endpoint: 'https://script.google.com/macros/s/test/exec', secret: 'test-only',
      fetchImpl: async () => ({ ok: true, text: async () => JSON.stringify(snapshot) }) })
    expect(result.changedYears).toEqual([2025, 2026])
    const digestData = await loadAllTimeData({ rootDir: root })
    expect(digestData.memberTotals.Rene.totalRuns).toBe(11)
    expect(digestData.memberTotals.Rene.totalKm).toBeCloseTo(79.2)
    expect(findUpcomingMilestones(digestData.memberTotals, digestData.runs, getAttendanceCutoff(digestData.runs))).toEqual([])
    expect(await readFile(join(root, 'public/data/2025.csv'), 'utf8')).toContain('"Beach, ""north""\nMeeting point"')
  } finally { await rm(root, { recursive: true, force: true }) }
})
