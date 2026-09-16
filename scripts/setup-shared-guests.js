#!/usr/bin/env node
// Operator-only setup. Never retry structural writes after dispatch starts.
import { createHash, randomUUID } from 'node:crypto'
import { constants } from 'node:fs'
import { open, lstat, realpath } from 'node:fs/promises'
import { dirname, isAbsolute, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import GuestOps from '../apps-script/GuestOps.js'
import { validateSnapshot } from './sync-attendance-snapshot.js'

const MAX_BYTES = 5_000_000
const sha256 = value => createHash('sha256').update(value).digest('hex')
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right)
class SetupError extends Error {}
const fail = code => { throw new SetupError(`Setup stopped (${code}). Preserve the private request and dispatch files.`) }

/** Parse an exact endpoint and integer IDs; never echo arguments in errors. */
function argumentsOf(args) {
  const [mode, ...rest] = args, values = {}
  if (!['prepare', 'read', 'submit', 'status'].includes(mode) || rest.length !== 8) fail('arguments')
  for (let i = 0; i < rest.length; i += 2) {
    if (!['--file', '--endpoint', '--spreadsheet', '--seasons'].includes(rest[i]) || values[rest[i]]) fail('arguments')
    values[rest[i]] = rest[i + 1]
  }
  const endpoint = values['--endpoint'], spreadsheetId = values['--spreadsheet'], file = values['--file']
  if (typeof endpoint !== 'string' || !/^https:\/\/script\.google\.com\/macros\/s\/[A-Za-z0-9_-]+\/exec$/.test(endpoint)) fail('endpoint')
  if (typeof spreadsheetId !== 'string' || !/^[A-Za-z0-9_-]+$/.test(spreadsheetId)) fail('workbook')
  if (typeof file !== 'string' || !isAbsolute(file) || resolve(file) !== file) fail('private_file')
  if (!/^(0|[1-9]\d*)(,(0|[1-9]\d*))*$/.test(values['--seasons'] || '')) fail('seasons')
  const seasonSheetIds = values['--seasons'].split(',').map(Number).sort((a, b) => a - b)
  if (seasonSheetIds.some(id => !Number.isSafeInteger(id)) || new Set(seasonSheetIds).size !== seasonSheetIds.length) fail('seasons')
  return { mode, file, endpoint, spreadsheetId, seasonSheetIds }
}

/** A private real directory and no-follow file handles prevent accidental sharing. */
async function privateDirectory(file) {
  const directory = dirname(file), info = await lstat(directory)
  if (!info.isDirectory() || (info.mode & 0o777) !== 0o700 || info.uid !== process.getuid() || await realpath(directory) !== directory) fail('private_file')
}
async function readPrivate(file, missingAllowed = false) {
  let handle
  try {
    handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW)
    const info = await handle.stat()
    if (!info.isFile() || (info.mode & 0o777) !== 0o600 || info.uid !== process.getuid() || info.size > 16_384 || info.nlink !== 1) fail('private_file')
    const value = JSON.parse(await handle.readFile('utf8'))
    if (!value || typeof value !== 'object' || Array.isArray(value)) fail('private_file')
    return value
  } catch (error) {
    if (missingAllowed && error.code === 'ENOENT') return null
    if (error instanceof SetupError) throw error
    fail('private_file')
  } finally { await handle?.close() }
}
async function saveExclusive(file, value, existingAllowed = false) {
  let handle
  try {
    handle = await open(file, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600)
    await handle.writeFile(JSON.stringify(value, null, 2) + '\n')
    await handle.sync()
    // Persist the directory entry too, before the first request can leave this process.
    const directory = await open(dirname(file), constants.O_RDONLY)
    try { await directory.sync() } finally { await directory.close() }
    return true
  } catch (error) {
    if (existingAllowed && error.code === 'EEXIST') return false
    fail('private_file')
  } finally { await handle?.close() }
}
function keysAre(value, keys) {
  return value && typeof value === 'object' && !Array.isArray(value) && same(Object.keys(value).sort(), keys.sort())
}
function validatedRecord(record, binding) {
  try {
    if (!keysAre(record, ['schemaVersion', 'endpoint', 'canonicalRequest', 'request']) || record.schemaVersion !== 1 ||
        record.endpoint !== binding.endpoint || !keysAre(record.request,
          ['apiVersion', 'operationId', 'action', 'spreadsheetId', 'seasonSheetIds', 'requestDigest'])) fail('binding')
    const request = record.request
    if (request.action !== 'setupSharedGuests' || request.spreadsheetId !== binding.spreadsheetId ||
        !same(request.seasonSheetIds, binding.seasonSheetIds) || !GuestOps.validateOperationRequest(request).ok ||
        GuestOps.canonicalRequest(request) !== record.canonicalRequest || sha256(record.canonicalRequest) !== request.requestDigest) fail('binding')
    return record
  } catch { fail('binding') }
}
function markerOf(record) {
  return { operationId: record.request.operationId, requestDigest: record.request.requestDigest,
    recordDigest: sha256(GuestOps.canonicalJSON(record)) }
}
function validateMarker(marker, record) {
  if (!keysAre(marker, ['operationId', 'requestDigest', 'recordDigest']) || !same(marker, markerOf(record))) fail('binding')
}

/** Only Google's ContentService 302/303 redirect may be followed, as a body-free GET. */
async function post(record, fields, secret, fetchImpl) {
  let response
  try {
    response = await fetchImpl(record.endpoint, { method: 'POST', redirect: 'manual',
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...fields, secret }),
      signal: AbortSignal.timeout(60_000) })
    if ([302, 303].includes(response.status)) {
      const target = new URL(response.headers.get('location'))
      if (target.protocol !== 'https:' || target.hostname !== 'script.googleusercontent.com' || target.port ||
          target.username || target.password || target.pathname !== '/macros/echo' || target.hash) fail('uncertain')
      response = await fetchImpl(target.href, { method: 'GET', redirect: 'manual', signal: AbortSignal.timeout(60_000) })
    }
    if (!response.ok) fail('uncertain')
    const text = await response.text()
    if (Buffer.byteLength(text) > MAX_BYTES) fail('uncertain')
    response = JSON.parse(text)
  } catch { fail('uncertain') }
  if (response?.ok === false) {
    const reason = ['bad_secret', 'busy', 'setup_disabled', 'not_applied'].includes(response.error) ? response.error : 'service_error'
    fail(reason)
  }
  if (response?.ok !== true) fail('uncertain')
  return response
}
function summary(record, status) {
  return { status, operationId: record.request.operationId, requestDigest: record.request.requestDigest }
}
async function operationStatus(record, secret, fetchImpl) {
  const response = await post(record, { action: 'getOperationStatus', apiVersion: 2, operationId: record.request.operationId }, secret, fetchImpl)
  const operation = response.operation
  if (operation === null) return summary(record, 'missing')
  if (!operation || operation.operationId !== record.request.operationId || operation.requestDigest !== record.request.requestDigest ||
      !['pending', 'completed', 'rejected', 'not_applied'].includes(operation.status)) fail('receipt_binding')
  if (operation.status !== 'completed') return summary(record, operation.status)
  const receipt = operation.response
  if (receipt?.ok !== true || receipt.status !== 'completed' || receipt.operationId !== record.request.operationId ||
      receipt.spreadsheetId !== record.request.spreadsheetId || !same(receipt.seasonSheetIds, record.request.seasonSheetIds) ||
      receipt.sharedGuestsEnabled !== false) fail('receipt_binding')
  return { ...summary(record, 'completed'), spreadsheetId: receipt.spreadsheetId,
    seasonSheetIds: receipt.seasonSheetIds, sharedGuestsEnabled: false }
}
async function verifyReads(record, secret, fetchImpl) {
  const state = await post(record, { action: 'getState', apiVersion: 2 }, secret, fetchImpl)
  if (state.apiVersion !== 2 || state.capabilities?.apiVersion !== 2 || state.capabilities.sharedGuests !== false || state.pendingOperationId) fail('read_gate')
  const snapshot = await post(record, { action: 'exportAttendanceSnapshot', apiVersion: 2 }, secret, fetchImpl)
  let seasons
  try { seasons = validateSnapshot(snapshot) } catch { fail('read_gate') }
  const ids = seasons.map(season => season.seasonSheetId).sort((a, b) => a - b)
  if (snapshot.spreadsheetId !== record.request.spreadsheetId || !same(ids, record.request.seasonSheetIds)) fail('read_gate')
  return { ...summary(record, 'read_verified'), spreadsheetId: snapshot.spreadsheetId,
    seasonSheetIds: ids, years: seasons.map(season => season.year), snapshotRevision: snapshot.snapshotRevision,
    sharedGuestsEnabled: false }
}

/** All modes require the same explicit binding; credentials only enter HTTP memory. */
export async function runSetup(args, { env = process.env, fetchImpl = globalThis.fetch } = {}) {
  try {
    const binding = argumentsOf(args)
    await privateDirectory(binding.file)
    if (binding.mode === 'prepare') {
      // Refuse even an orphaned marker; deleting a request must not reset dispatch state.
      if (await readPrivate(binding.file + '.dispatch', true)) fail('private_file')
      const request = { apiVersion: 2, operationId: randomUUID(), action: 'setupSharedGuests',
        spreadsheetId: binding.spreadsheetId, seasonSheetIds: binding.seasonSheetIds }
      const canonicalRequest = GuestOps.canonicalRequest(request)
      request.requestDigest = sha256(canonicalRequest)
      const record = { schemaVersion: 1, endpoint: binding.endpoint, canonicalRequest, request }
      await saveExclusive(binding.file, record)
      return { ...summary(record, 'prepared'), endpoint: record.endpoint,
        spreadsheetId: request.spreadsheetId, seasonSheetIds: request.seasonSheetIds }
    }
    const record = validatedRecord(await readPrivate(binding.file), binding)
    const marker = await readPrivate(binding.file + '.dispatch', true)
    if (marker) validateMarker(marker, record)
    const secret = env.FCTC_SETUP_SECRET
    if (typeof secret !== 'string' || !secret.trim()) fail('missing_secret')
    if (binding.mode === 'read') return await verifyReads(record, secret, fetchImpl)
    if (binding.mode === 'status' || marker) return await operationStatus(record, secret, fetchImpl)
    // Exclusive creation serialises concurrent invocations. A crash from here on
    // leaves only status reads available, even if the original POST never arrived.
    if (!await saveExclusive(binding.file + '.dispatch', markerOf(record), true)) {
      validateMarker(await readPrivate(binding.file + '.dispatch'), record)
      return await operationStatus(record, secret, fetchImpl)
    }
    await post(record, record.request, secret, fetchImpl)
    // Never trust the mutation response alone. Require a digest-bound status receipt.
    return await operationStatus(record, secret, fetchImpl)
  } catch (error) {
    if (error instanceof SetupError) throw error
    fail('local_error')
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runSetup(process.argv.slice(2)).then(result => console.log(JSON.stringify(result, null, 2)))
    .catch(error => { console.error(error.message); process.exitCode = 1 })
}
