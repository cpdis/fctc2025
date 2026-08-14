// @vitest-environment node

import { describe, expect, it, vi } from 'vitest'
import { ResendBatchError, sendResendBatch } from './resendBatch.js'

const ITEMS = [
  {
    from: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
    to: ['first@example.com'],
    subject: 'Milestone week',
    text: 'Private milestone content',
  },
  {
    from: 'FCTC Milestones <runs@notifications.fctc.cpd.dev>',
    to: ['second@example.com'],
    subject: 'Milestone week',
    text: 'Private milestone content',
  },
]

function response(status, body, headers = {}) {
  const normalizedHeaders = Object.fromEntries(
    Object.entries(headers).map(([name, value]) => [name.toLowerCase(), value])
  )

  return {
    ok: status >= 200 && status < 300,
    status,
    headers: { get: (name) => normalizedHeaders[name.toLowerCase()] ?? null },
    text: vi.fn().mockResolvedValue(
      typeof body === 'string' ? body : JSON.stringify(body)
    ),
  }
}

function requestOptions(overrides = {}) {
  return {
    apiKey: 're_private_key',
    items: ITEMS,
    idempotencyKey: 'fctc-milestones/2026-08-17',
    sleep: vi.fn().mockResolvedValue(undefined),
    random: () => 0,
    now: () => Date.parse('2026-08-16T09:00:00Z'),
    ...overrides,
  }
}

describe('sendResendBatch', () => {
  it('posts one deterministic batch and accepts one valid ID per item', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(response(200, {
      data: [{ id: 'email-one' }, { id: 'email-two' }],
    }))

    await expect(sendResendBatch(requestOptions({ fetchImpl }))).resolves.toEqual({
      acceptedCount: 2,
    })

    const [url, options] = fetchImpl.mock.calls[0]
    expect(url).toBe('https://api.resend.com/emails/batch')
    expect(options.method).toBe('POST')
    expect(options.headers).toMatchObject({
      Authorization: 'Bearer re_private_key',
      'Content-Type': 'application/json',
      'Idempotency-Key': 'fctc-milestones/2026-08-17',
      'User-Agent': 'fctc-dashboard-milestone-notifier/1.0',
    })
    expect(JSON.parse(options.body)).toEqual(ITEMS)
  })

  it.each([
    ['missing items', { data: [{ id: 'email-one' }] }],
    ['extra items', { data: [{ id: 'one' }, { id: 'two' }, { id: 'three' }] }],
    ['blank ID', { data: [{ id: 'one' }, { id: '' }] }],
    ['whitespace ID', { data: [{ id: 'one' }, { id: '   ' }] }],
    ['wrong shape', { data: 'not-an-array' }],
  ])('rejects a malformed success response: %s', async (_label, body) => {
    const fetchImpl = vi.fn().mockResolvedValue(response(200, body))

    await expect(sendResendBatch(requestOptions({ fetchImpl }))).rejects.toMatchObject({
      category: 'malformed_response',
      attempts: 1,
    })
    expect(fetchImpl).toHaveBeenCalledTimes(1)
  })

  it('rejects a non-JSON success response without exposing it', async () => {
    const rawBody = 'private raw provider response'
    const fetchImpl = vi.fn().mockResolvedValue(response(200, rawBody))

    const error = await sendResendBatch(requestOptions({ fetchImpl })).catch((value) => value)

    expect(error).toBeInstanceOf(ResendBatchError)
    expect(error.category).toBe('malformed_response')
    expect(error.message).not.toContain(rawBody)
  })

  it('cancels a provider response that exceeds the safe byte limit', async () => {
    const cancel = vi.fn().mockResolvedValue(undefined)
    const reader = {
      read: vi.fn()
        .mockResolvedValueOnce({ done: false, value: new Uint8Array(129 * 1024) })
        .mockResolvedValueOnce({ done: true }),
      cancel,
    }
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: { get: () => null },
      body: { getReader: () => reader },
      text: vi.fn(() => { throw new Error('stream response must not use text()') }),
    })

    await expect(sendResendBatch(requestOptions({ fetchImpl }))).rejects.toMatchObject({
      category: 'malformed_response',
    })
    expect(cancel).toHaveBeenCalledTimes(1)
  })

  it.each([
    ['HTTP 408', 408, { name: 'request_timeout' }],
    ['HTTP 429', 429, { name: 'rate_limit_exceeded' }],
    ['HTTP 500', 500, { name: 'application_error' }],
    ['concurrent HTTP 409', 409, { name: 'concurrent_idempotent_requests' }],
  ])('retries %s with the same payload and key', async (_label, status, body) => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(response(status, body))
      .mockResolvedValueOnce(response(200, { data: [{ id: 'one' }, { id: 'two' }] }))
    const options = requestOptions({ fetchImpl })

    await expect(sendResendBatch(options)).resolves.toEqual({ acceptedCount: 2 })

    expect(fetchImpl).toHaveBeenCalledTimes(2)
    expect(fetchImpl.mock.calls[1][1].body).toBe(fetchImpl.mock.calls[0][1].body)
    expect(fetchImpl.mock.calls[1][1].headers['Idempotency-Key'])
      .toBe(fetchImpl.mock.calls[0][1].headers['Idempotency-Key'])
    expect(options.sleep).toHaveBeenCalledTimes(1)
  })

  it('caps Retry-After at 30 seconds', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(response(429, { name: 'rate_limit_exceeded' }, {
        'Retry-After': '60',
      }))
      .mockResolvedValueOnce(response(200, { data: [{ id: 'one' }, { id: 'two' }] }))
    const options = requestOptions({ fetchImpl })

    await sendResendBatch(options)

    expect(options.sleep).toHaveBeenCalledWith(30_000)
  })

  it.each([
    ['HTTP 401', 401, { name: 'invalid_api_key' }, 'authentication'],
    ['HTTP 403', 403, { name: 'restricted_api_key' }, 'authorization'],
    ['HTTP 422', 422, { name: 'validation_error' }, 'validation'],
    ['changed-payload HTTP 409', 409, { name: 'invalid_idempotent_request' }, 'idempotency_conflict'],
  ])('does not retry %s', async (_label, status, body, category) => {
    const rawBody = JSON.stringify({ ...body, message: 'private provider detail' })
    const fetchImpl = vi.fn().mockResolvedValue(response(status, rawBody))

    const error = await sendResendBatch(requestOptions({ fetchImpl })).catch((value) => value)

    expect(fetchImpl).toHaveBeenCalledTimes(1)
    expect(error).toMatchObject({ category, status, attempts: 1 })
    expect(error.message).not.toContain('private provider detail')
  })

  it('retries a network failure and stops after three attempts', async () => {
    const fetchImpl = vi.fn().mockRejectedValue(new TypeError('secret network detail'))
    const options = requestOptions({ fetchImpl })

    const error = await sendResendBatch(options).catch((value) => value)

    expect(fetchImpl).toHaveBeenCalledTimes(3)
    expect(options.sleep).toHaveBeenCalledTimes(2)
    expect(error).toMatchObject({ category: 'network', attempts: 3 })
    expect(error.message).not.toContain('secret network detail')
  })

  it('aborts timed-out attempts and reports a fixed timeout category', async () => {
    vi.useFakeTimers()
    const fetchImpl = vi.fn((_url, { signal }) => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => {
        reject(new DOMException('private timeout detail', 'AbortError'))
      })
    }))
    const promise = sendResendBatch(requestOptions({ fetchImpl, timeoutMs: 10 }))
      .catch((value) => value)

    await vi.runAllTimersAsync()
    const error = await promise
    vi.useRealTimers()

    expect(fetchImpl).toHaveBeenCalledTimes(3)
    expect(error).toMatchObject({ category: 'timeout', attempts: 3 })
    expect(error.message).not.toContain('private timeout detail')
  })
})
