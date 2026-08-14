const RESEND_BATCH_URL = 'https://api.resend.com/emails/batch'
const USER_AGENT = 'fctc-dashboard-milestone-notifier/1.0'
const DEFAULT_TIMEOUT_MS = 10_000
const DEFAULT_MAX_ATTEMPTS = 3
const MAX_RETRY_DELAY_MS = 30_000

/**
 * A provider failure that is safe to expose in public workflow logs.
 * Raw response content and the underlying network message are never retained.
 */
export class ResendBatchError extends Error {
  constructor(category, { status = null, attempts = 1 } = {}) {
    const statusText = status === null ? '' : ` status=${status}`
    super(`Resend batch failed category=${category}${statusText}`)
    this.name = 'ResendBatchError'
    this.category = category
    this.status = status
    this.attempts = attempts
  }
}

/**
 * Submit one deterministic Resend batch with bounded, idempotent retries.
 * The caller supplies already validated items and owns all public logging.
 */
export async function sendResendBatch({
  apiKey,
  items,
  idempotencyKey,
  fetchImpl = globalThis.fetch,
  sleep = defaultSleep,
  random = Math.random,
  now = Date.now,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  maxAttempts = DEFAULT_MAX_ATTEMPTS,
}) {
  assertRequestInputs({ apiKey, items, idempotencyKey, fetchImpl, timeoutMs, maxAttempts })

  // Serialize once. Every retry must use the same bytes and idempotency key.
  const body = JSON.stringify(items)

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), timeoutMs)
    let response

    try {
      response = await fetchImpl(RESEND_BATCH_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
          'User-Agent': USER_AGENT,
        },
        body,
        signal: controller.signal,
      })
    } catch (error) {
      clearTimeout(timeout)
      const category = controller.signal.aborted || error?.name === 'AbortError'
        ? 'timeout'
        : 'network'

      if (attempt === maxAttempts) {
        throw new ResendBatchError(category, { attempts: attempt })
      }

      await sleep(backoffDelay(attempt, random))
      continue
    }

    clearTimeout(timeout)
    const responseText = await readResponseText(response)

    if (response.ok) {
      const parsed = parseJson(responseText)
      if (!hasValidSuccessShape(parsed, items.length)) {
        throw new ResendBatchError('malformed_response', {
          status: response.status,
          attempts: attempt,
        })
      }
      return { acceptedCount: parsed.data.length }
    }

    const providerType = readProviderType(responseText)
    const decision = classifyFailure(response.status, providerType)

    if (!decision.retryable || attempt === maxAttempts) {
      throw new ResendBatchError(decision.category, {
        status: response.status,
        attempts: attempt,
      })
    }

    const retryAfter = parseRetryAfter(response.headers?.get?.('Retry-After'), now())
    await sleep(retryAfter ?? backoffDelay(attempt, random))
  }

  // The bounded loop always returns or throws. Keep a fail-closed guard for
  // future edits that could change its control flow.
  throw new ResendBatchError('internal', { attempts: maxAttempts })
}

function assertRequestInputs({ apiKey, items, idempotencyKey, fetchImpl, timeoutMs, maxAttempts }) {
  if (typeof apiKey !== 'string' || apiKey.length === 0 || /[\r\n\0]/.test(apiKey)) {
    throw new ResendBatchError('configuration')
  }
  if (!Array.isArray(items) || items.length === 0 || items.length > 100) {
    throw new ResendBatchError('configuration')
  }
  if (typeof idempotencyKey !== 'string' || idempotencyKey.length === 0 ||
      idempotencyKey.length > 256 || /[\r\n\0]/.test(idempotencyKey)) {
    throw new ResendBatchError('configuration')
  }
  if (typeof fetchImpl !== 'function' || !Number.isFinite(timeoutMs) || timeoutMs <= 0 ||
      !Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 3) {
    throw new ResendBatchError('configuration')
  }
}

async function readResponseText(response) {
  try {
    return await response.text()
  } catch {
    return ''
  }
}

function parseJson(value) {
  try {
    return JSON.parse(value)
  } catch {
    return null
  }
}

function hasValidSuccessShape(value, expectedCount) {
  return value !== null && Array.isArray(value.data) && value.data.length === expectedCount &&
    value.data.every((item) => typeof item?.id === 'string' && item.id.trim().length > 0)
}

function readProviderType(responseText) {
  const parsed = parseJson(responseText)
  const type = parsed?.name ?? parsed?.type
  return typeof type === 'string' ? type : null
}

function classifyFailure(status, providerType) {
  if (status === 408) return { retryable: true, category: 'temporary_http' }
  if (status === 429) return { retryable: true, category: 'rate_limited' }
  if (status >= 500 && status <= 599) {
    return { retryable: true, category: 'provider_temporary' }
  }
  if (status === 409 && providerType === 'concurrent_idempotent_requests') {
    return { retryable: true, category: 'idempotency_busy' }
  }
  if (status === 401) return { retryable: false, category: 'authentication' }
  if (status === 403) return { retryable: false, category: 'authorization' }
  if (status === 409) return { retryable: false, category: 'idempotency_conflict' }
  if (status === 422) return { retryable: false, category: 'validation' }
  return { retryable: false, category: 'provider_rejected' }
}

function parseRetryAfter(value, nowMs) {
  if (typeof value !== 'string' || value.trim() === '') return null

  const seconds = Number(value)
  if (Number.isFinite(seconds) && seconds >= 0) {
    return Math.min(Math.round(seconds * 1000), MAX_RETRY_DELAY_MS)
  }

  const dateMs = Date.parse(value)
  if (Number.isNaN(dateMs)) return null
  return Math.min(Math.max(dateMs - nowMs, 0), MAX_RETRY_DELAY_MS)
}

function backoffDelay(attempt, random) {
  const jitter = Math.floor(Math.max(0, Math.min(1, random())) * 250)
  return Math.min(1000 * (2 ** (attempt - 1)) + jitter, MAX_RETRY_DELAY_MS)
}

function defaultSleep(delayMs) {
  return new Promise((resolve) => setTimeout(resolve, delayMs))
}
