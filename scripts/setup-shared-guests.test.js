// @vitest-environment node
import { createHash } from 'node:crypto'
import { createRequire } from 'node:module'
import { mkdtemp, readFile, stat, chmod, writeFile, rm, realpath, symlink } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, expect, it } from 'vitest'
import { runSetup } from './setup-shared-guests.js'
const require = createRequire(import.meta.url)
const GuestOps = require('../apps-script/GuestOps.js')
const { createEnvironment } = require('../apps-script/test/support/fakeAppsScript.js')
const endpoint = 'https://script.google.com/macros/s/synthetic-deployment/exec'
const secret = 'synthetic-private-secret'
const roots = []
afterEach(async () => { for (const root of roots.splice(0)) await rm(root, { recursive: true, force: true }) })
async function fixture() {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'fctc-setup-'))); roots.push(root)
  const file = join(root, 'request.json')
  const args = ['--file', file, '--endpoint', endpoint, '--spreadsheet', 'test-workbook', '--seasons', '25,26']
  const grid = [['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', 'Col', "+1's", 'Total Attendance per run'],
    ['Fri, 3-Jan', 'Beach', 'Soft Sand', 7.5, 7.2, 'x', 1, 2]]
  const env = createEnvironment({ grid, sheetName: '2026', sheetId: 26,
    extraSheets: [{ name: '2025', sheetId: 25, grid }],
    properties: { SHARED_SECRET: secret, SHARED_GUESTS_SETUP_ALLOWED: 'true' } })
  const calls = []
  const fetchImpl = async (url, options) => {
    const request = JSON.parse(options.body); calls.push(request)
    const body = JSON.stringify(env.post(request))
    return { ok: true, status: 200, text: async () => body }
  }
  const invoke = (mode, overrides = {}) => runSetup([mode, ...args], { env: { FCTC_SETUP_SECRET: secret }, fetchImpl, ...overrides })
  return { root, file, args, env, calls, fetchImpl, invoke }
}

it('persists production canonical bytes, digest and UUID privately without the secret', async () => {
  const f = await fixture(); const result = await f.invoke('prepare')
  const saved = JSON.parse(await readFile(f.file, 'utf8'))
  expect(saved.canonicalRequest).toBe(GuestOps.canonicalRequest(saved.request))
  expect(saved.request.requestDigest).toBe(createHash('sha256').update(saved.canonicalRequest).digest('hex'))
  expect(GuestOps.validateOperationRequest(saved.request).ok).toBe(true)
  expect(saved.request.seasonSheetIds).toEqual([25, 26])
  expect(saved.endpoint).toBe(endpoint)
  expect((await stat(f.file)).mode & 0o777).toBe(0o600)
  expect(JSON.stringify(saved) + JSON.stringify(result)).not.toContain(secret)
  expect(f.calls).toHaveLength(0)
  await expect(f.invoke('prepare')).rejects.toThrow('private_file')
})

it('saves dispatch evidence before the only setup POST and verifies the real router receipt', async () => {
  const f = await fixture(); await f.invoke('prepare')
  const result = await f.invoke('submit', { fetchImpl: async (url, options) => {
    const marker = JSON.parse(await readFile(f.file + '.dispatch', 'utf8'))
    const saved = JSON.parse(await readFile(f.file, 'utf8'))
    expect(marker.operationId).toBe(saved.request.operationId)
    expect(marker.requestDigest).toBe(saved.request.requestDigest)
    expect((await stat(f.file + '.dispatch')).mode & 0o777).toBe(0o600)
    return f.fetchImpl(url, options)
  } })
  expect(result.status).toBe('completed')
  expect(result.sharedGuestsEnabled).toBe(false)
  expect(result.seasonSheetIds).toEqual([25, 26])
  expect(f.calls.map(call => call.action)).toEqual(['setupSharedGuests', 'getOperationStatus'])
  expect((await f.invoke('submit')).status).toBe('completed')
  expect(f.calls.filter(call => call.action === 'setupSharedGuests')).toHaveLength(1)
})

it('uses status only after a lost response and restart, even when the receipt is absent', async () => {
  const f = await fixture(); await f.invoke('prepare')
  const thrown = await f.invoke('submit', { fetchImpl: async () => { throw new Error(secret) } }).catch(error => error)
  expect(thrown.message).toContain('uncertain')
  expect(thrown.message).not.toContain(secret)
  expect((await f.invoke('submit')).status).toBe('missing')
  expect((await f.invoke('status')).status).toBe('missing')
  expect(f.calls.map(call => call.action)).toEqual(['getOperationStatus', 'getOperationStatus'])
})

it('resolves an applied operation after the response is lost without repeating setup', async () => {
  const f = await fixture(); await f.invoke('prepare')
  await expect(f.invoke('submit', { fetchImpl: async (url, options) => {
    await f.fetchImpl(url, options); throw new Error(secret)
  } })).rejects.toThrow('uncertain')
  expect((await f.invoke('submit')).status).toBe('completed')
  expect(f.calls.map(call => call.action)).toEqual(['setupSharedGuests', 'getOperationStatus'])
})

it('keeps authentication rejection secret-safe and prevents subsequent setup dispatch', async () => {
  const f = await fixture(); await f.invoke('prepare')
  await expect(f.invoke('submit', { env: { FCTC_SETUP_SECRET: 'wrong' } })).rejects.toThrow('bad_secret')
  expect((await f.invoke('submit')).status).toBe('missing')
  expect(f.calls.filter(call => call.action === 'setupSharedGuests')).toHaveLength(1)
})

it('verifies v2 read and all-season snapshot before setup with shared writes disabled', async () => {
  const f = await fixture(); await f.invoke('prepare')
  const result = await f.invoke('read')
  expect(result.status).toBe('read_verified')
  expect(result.seasonSheetIds).toEqual([25, 26])
  expect(f.calls.map(call => call.action)).toEqual(['getState', 'exportAttendanceSnapshot'])
  expect(JSON.stringify(result)).not.toContain('Soft Sand')
  f.env.properties.SHARED_GUESTS_ENABLED = 'true'
  await expect(f.invoke('read')).rejects.toThrow('read_gate')
})

it.each([
  ['--endpoint', 'https://example.com/macros/s/test/exec'],
  ['--endpoint', endpoint + '?secret=wrong'],
  ['--endpoint', endpoint.replace('https:', 'http:')],
  ['--endpoint', endpoint.replace('script.google.com', 'script.google.com:443')],
  ['--seasons', '25,25'], ['--seasons', '25,26.1'], ['--seasons', '-1,26'],
  ['--spreadsheet', '../private'], ['--secret', secret],
])('rejects invalid CLI input without echoing it: %s', async (flag, value) => {
  const f = await fixture(); const args = [...f.args]
  const index = args.indexOf(flag)
  if (index >= 0) args[index + 1] = value; else args.push(flag, value)
  const error = await runSetup(['prepare', ...args], { env: {} }).catch(error => error)
  expect(error).toBeInstanceOf(Error)
  expect(error.message).not.toContain(secret)
  expect(f.calls).toHaveLength(0)
})

it('refuses permission, request, endpoint and dispatch-binding changes before network use', async () => {
  const f = await fixture(); await f.invoke('prepare')
  await chmod(f.file, 0o644)
  await expect(f.invoke('submit')).rejects.toThrow('private_file')
  await chmod(f.file, 0o600)
  await expect(runSetup(['submit', ...f.args.map(arg => arg === endpoint ? endpoint.replace('synthetic', 'other') : arg)],
    { env: { FCTC_SETUP_SECRET: secret }, fetchImpl: f.fetchImpl })).rejects.toThrow('binding')
  const original = await readFile(f.file, 'utf8'); const saved = JSON.parse(original)
  saved.request.seasonSheetIds = [26]
  await writeFile(f.file, JSON.stringify(saved))
  await expect(f.invoke('submit')).rejects.toThrow('binding')
  await writeFile(f.file, original)
  await writeFile(f.file + '.dispatch', '{}', { mode: 0o600 })
  await expect(f.invoke('submit')).rejects.toThrow('binding')
  expect(f.calls).toHaveLength(0)
})

it.each(['operationId', 'requestDigest', 'spreadsheetId', 'seasonSheetIds', 'sharedGuestsEnabled'])(
  'rejects a completed receipt with changed %s', async field => {
    const f = await fixture(); await f.invoke('prepare'); await f.invoke('submit')
    const fetchImpl = async (url, options) => {
      const response = await f.fetchImpl(url, options); const body = JSON.parse(await response.text())
      if (['operationId', 'requestDigest'].includes(field)) body.operation[field] = 'other'
      else body.operation.response[field] = field === 'seasonSheetIds' ? [26] : field === 'sharedGuestsEnabled' ? true : 'other'
      return { ok: true, status: 200, text: async () => JSON.stringify(body) }
    }
    await expect(f.invoke('status', { fetchImpl })).rejects.toThrow('receipt_binding')
  })

it('does not forward a secret to redirects, and never follows redirects with a POST', async () => {
  const f = await fixture(); await f.invoke('prepare'); const calls = []
  await expect(f.invoke('submit', { fetchImpl: async (url, options) => {
    calls.push(options)
    return { status: 307, headers: { get: () => 'https://example.com/' } }
  } })).rejects.toThrow('uncertain')
  expect(calls).toHaveLength(1)
  expect(calls[0].redirect).toBe('manual')
})

it('follows a Google content redirect using a body-free GET', async () => {
  const f = await fixture(); await f.invoke('prepare'); const calls = []
  const result = await f.invoke('status', { fetchImpl: async (url, options) => {
    calls.push({ url, options })
    return options.method === 'POST'
      ? { status: 302, headers: { get: () => 'https://script.googleusercontent.com/macros/echo?user_content_key=synthetic' } }
      : { ok: true, status: 200, text: async () => '{"ok":true,"operation":null}' }
  } })
  expect(result.status).toBe('missing')
  expect(calls.map(call => call.options.method)).toEqual(['POST', 'GET'])
  expect(calls[1].options.body).toBeUndefined()
  expect(JSON.stringify(calls[1])).not.toContain(secret)
})

it('rejects an untrusted 302 redirect without contacting its target', async () => {
  const f = await fixture(); await f.invoke('prepare'); let count = 0
  await expect(f.invoke('status', { fetchImpl: async () => {
    count++
    return { status: 302, headers: { get: () => 'https://example.com/macros/echo' } }
  } })).rejects.toThrow('uncertain')
  expect(count).toBe(1)
})

it('sanitizes service error bodies and requires the environment secret before dispatch', async () => {
  const f = await fixture(); await f.invoke('prepare')
  await expect(f.invoke('submit', { env: {} })).rejects.toThrow('missing_secret')
  await expect(stat(f.file + '.dispatch')).rejects.toMatchObject({ code: 'ENOENT' })
  const error = await f.invoke('status', { fetchImpl: async () => ({ ok: true, status: 200,
    text: async () => JSON.stringify({ ok: false, error: secret, message: secret }) }) }).catch(error => error)
  expect(error.message).toContain('service_error')
  expect(error.message).not.toContain(secret)
  expect(await readFile(f.file, 'utf8')).not.toContain(secret)
})

it('never dispatches setup twice when two processes race for its marker', async () => {
  const f = await fixture(); await f.invoke('prepare')
  const results = await Promise.allSettled([f.invoke('submit'), f.invoke('submit')])
  expect(results.some(result => result.status === 'fulfilled' && result.value.status === 'completed')).toBe(true)
  expect(f.calls.filter(call => call.action === 'setupSharedGuests')).toHaveLength(1)
  expect((await f.invoke('submit')).status).toBe('completed')
})

it('rejects shared directories and symlink request files without network use', async () => {
  const f = await fixture(); await f.invoke('prepare')
  await chmod(f.root, 0o755)
  await expect(f.invoke('status')).rejects.toThrow('private_file')
  await chmod(f.root, 0o700)
  const alias = join(f.root, 'alias.json'); await symlink(f.file, alias)
  await expect(runSetup(['status', ...f.args.map(arg => arg === f.file ? alias : arg)],
    { env: { FCTC_SETUP_SECRET: secret }, fetchImpl: f.fetchImpl })).rejects.toThrow('private_file')
  expect(f.calls).toHaveLength(0)
})

it.each(['pending', 'rejected', 'not_applied'])('preserves %s as a status-only result', async status => {
  const f = await fixture(); await f.invoke('prepare')
  await expect(f.invoke('submit', { fetchImpl: async () => { throw new Error('lost') } })).rejects.toThrow('uncertain')
  const saved = JSON.parse(await readFile(f.file, 'utf8')); const calls = []
  const result = await f.invoke('submit', { fetchImpl: async (url, options) => {
    calls.push(JSON.parse(options.body).action)
    return { ok: true, status: 200, text: async () => JSON.stringify({ ok: true,
      operation: { operationId: saved.request.operationId, requestDigest: saved.request.requestDigest,
        status, response: status === 'pending' ? null : { ok: false, message: secret } } }) }
  } })
  expect(result.status).toBe(status)
  expect(calls).toEqual(['getOperationStatus'])
  expect(JSON.stringify(result)).not.toContain(secret)
})
